module Main exposing (main)

import Browser
import Browser.Events
import Config
import Dict
import Direction exposing (Direction(..))
import Entity exposing (Enemy(..), Entity(..), Floor(..), Item)
import Game exposing (Game)
import Game.Event exposing (Event(..), GameAndEvents)
import Game.Map
import Game.Update
import Gen.Sound as Sound exposing (Sound(..))
import Html exposing (Html)
import Html.Attributes
import Input exposing (Input(..))
import Json.Decode as Decode
import Layout
import Platform.Cmd as Cmd
import Port
import PortDefinition exposing (FromElm(..), ToElm(..))
import Process
import Random exposing (Seed)
import Set exposing (Set)
import Task
import Time
import View.Controls
import View.Screen as Screen



-------------------------------
-- MODEL
-------------------------------


type Overlay
    = Menu
    | GameWon


type alias Model =
    { game : Game
    , levelSeed : Seed
    , seed : Seed
    , overlay : Maybe Overlay
    , frame : Int
    , history : List Game
    , room : ( Int, Int )
    , initialItem : Maybe Item
    , initialPlayerPos : ( Int, Int )
    , hasKey : Bool
    , unlockedRooms : Set ( Int, Int )
    }


type Msg
    = Input Input
    | ApplyEvents (List Event)
    | GotSeed Seed
    | NextFrameRequested
    | NoOps
    | RoomEntered ( Int, Int )
    | Received (Result Decode.Error PortDefinition.ToElm)



-------------------------------
-- INIT
-------------------------------


init : flag -> ( Model, Cmd Msg )
init _ =
    let
        room =
            ( 0, 0 )

        initialPlayerPos =
            ( 2, 4 )

        seed =
            Random.initialSeed 42

        game =
            Game.Map.get room
    in
    ( { levelSeed = seed
      , seed = seed
      , game = game |> Game.addPlayer initialPlayerPos
      , initialItem = Nothing
      , initialPlayerPos = initialPlayerPos
      , overlay = Just Menu
      , frame = 0
      , history = []
      , room = room
      , hasKey = False
      , unlockedRooms = Set.empty
      }
    , Cmd.batch
        [ Port.fromElm (RegisterSounds Sound.asList)
        , Random.generate GotSeed Random.independentSeed
        ]
    )



-------------------------------
-- UPDATE
-------------------------------


startRoom : Game -> Model -> Model
startRoom game model =
    { model
        | game =
            { game | item = model.game.item }
                |> Game.addPlayer model.initialPlayerPos
                |> (if Dict.member model.initialPlayerPos game.floor then
                        identity

                    else
                        Game.addFloor model.initialPlayerPos Ground
                   )
        , overlay = Nothing
    }


restartRoom : Model -> ( Model, Cmd Msg )
restartRoom model =
    ( { model
        | game =
            model.game
                |> (\game ->
                        { game
                            | item = model.initialItem
                            , playerPos = Just model.initialPlayerPos
                        }
                   )
        , history = []
      }
        |> nextRoom model.room
    , PlaySound { sound = Retry, looping = False } |> Port.fromElm
    )


nextRoom : ( Int, Int ) -> Model -> Model
nextRoom room model =
    let
        game =
            Game.Map.get room

        playerPos =
            model.game.playerPos
                |> Maybe.map (\( x, y ) -> ( modBy Config.roomSize x, modBy Config.roomSize y ))
                |> Maybe.withDefault model.initialPlayerPos
    in
    { model
        | room = room
        , history = []
        , initialPlayerPos = playerPos
    }
        |> startRoom game


setGame : Model -> Game -> Model
setGame model game =
    { model
        | game = game
        , history = model.game :: model.history
    }


gotSeed : Seed -> Model -> Model
gotSeed seed model =
    { model | seed = seed }


nextFrameRequested : Model -> Model
nextFrameRequested model =
    { model | frame = model.frame + 1 |> modBy 2 }


applyGameAndKill : Model -> GameAndEvents -> ( Model, Cmd Msg )
applyGameAndKill model output =
    ( setGame model output.game
    , Process.sleep 100
        |> Task.perform (\() -> ApplyEvents output.kill)
    )


applyEvent : Event -> Model -> ( Model, Cmd Msg )
applyEvent event model =
    case event of
        Kill pos ->
            ( { model | game = Game.Event.kill pos model.game }
            , Cmd.none
            )

        Fx sound ->
            ( model
            , Port.fromElm
                (PlaySound
                    { sound = sound
                    , looping = False
                    }
                )
            )

        MoveToRoom room ->
            ( model
            , Cmd.batch
                [ Process.sleep 200 |> Task.perform (\() -> RoomEntered room)
                , PlaySound
                    { sound = Win
                    , looping = False
                    }
                    |> Port.fromElm
                ]
            )

        WinGame ->
            ( { model | overlay = Just GameWon }, Cmd.none )

        AddKey ->
            ( { model | hasKey = True }, Cmd.none )

        UnlockDoor ->
            ( { model
                | hasKey = False
                , unlockedRooms = model.unlockedRooms |> Set.insert model.room
              }
            , Cmd.none
            )

        Drop pos ->
            ( if Dict.member pos model.game.floor then
                model

              else
                case Game.get pos model.game of
                    Just Crate ->
                        { model
                            | game =
                                model.game
                                    |> Game.remove pos
                                    |> Game.addFloor pos CrateInLava
                        }

                    Just ActiveSmallBomb ->
                        { model
                            | game =
                                model.game
                                    |> Game.remove pos
                        }

                    _ ->
                        model
            , Cmd.none
            )


applyEvents : List Event -> Model -> ( Model, Cmd Msg )
applyEvents events model =
    events
        |> List.foldl
            (\event ( m, c1 ) ->
                applyEvent event m
                    |> Tuple.mapSecond
                        (\c2 ->
                            Cmd.batch [ c1, c2 ]
                        )
            )
            ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Input input ->
            case model.overlay of
                Just GameWon ->
                    ( model, Cmd.none )

                Just Menu ->
                    ( { model | overlay = Nothing }
                    , Cmd.none
                    )

                Nothing ->
                    if Game.isWon model.game then
                        --solvedRoom model
                        ( model, Cmd.none )

                    else
                        case input of
                            InputActivate ->
                                model.game
                                    |> Game.getPlayerPosition
                                    |> Maybe.andThen
                                        (\playerPosition ->
                                            model.game
                                                |> Game.Update.placeBombeAndUpdateGame
                                                    { roomUnlocked = Set.member model.room model.unlockedRooms }
                                                    playerPosition
                                                |> Maybe.map (applyGameAndKill model)
                                        )
                                    |> Maybe.withDefault ( model, Cmd.none )

                            InputDir dir ->
                                model.game
                                    |> Game.getPlayerPosition
                                    |> Maybe.andThen
                                        (\playerPosition ->
                                            model.game
                                                |> Game.Update.movePlayerInDirectionAndUpdateGame
                                                    { direction = dir
                                                    , hasKey = model.hasKey
                                                    , roomUnlocked = Set.member model.room model.unlockedRooms
                                                    }
                                                    playerPosition
                                                |> Maybe.map
                                                    (Game.Event.andThen
                                                        (\m -> { game = m, kill = [ Fx Move ] })
                                                    )
                                                |> Maybe.map (applyGameAndKill model)
                                        )
                                    |> Maybe.withDefault ( model, Cmd.none )

                            InputUndo ->
                                case model.history of
                                    head :: tail ->
                                        ( { model | game = head, history = tail }
                                        , PlaySound { sound = Undo, looping = False } |> Port.fromElm
                                        )

                                    [] ->
                                        ( model, Cmd.none )

                            InputReset ->
                                model
                                    |> restartRoom

                            InputOpenMap ->
                                ( model, Cmd.none )

        ApplyEvents events ->
            model
                |> applyEvents events

        NextFrameRequested ->
            ( nextFrameRequested model
            , Cmd.none
            )

        GotSeed seed ->
            ( gotSeed seed model, Cmd.none )

        NoOps ->
            ( model, Cmd.none )

        RoomEntered id ->
            ( nextRoom id model, Cmd.none )

        Received result ->
            case result of
                Ok (SoundEnded _) ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )



-------------------------------
-- SUBSCRIPTIONS
-------------------------------


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.map toDirection (Decode.field "key" Decode.string)


toDirection : String -> Msg
toDirection string =
    case string of
        "a" ->
            Input (InputDir Left)

        "LeftArrow" ->
            Input (InputDir Left)

        "d" ->
            Input (InputDir Right)

        "RightArrow" ->
            Input (InputDir Right)

        "w" ->
            Input (InputDir Up)

        "UpArrow" ->
            Input (InputDir Up)

        "s" ->
            Input (InputDir Down)

        "DownArrow" ->
            Input (InputDir Down)

        "y" ->
            Input InputUndo

        "z" ->
            Input InputUndo

        "c" ->
            Input InputUndo

        "r" ->
            Input InputReset

        -- "Escape" ->
        --    Input InputOpenMap
        " " ->
            Input InputActivate

        _ ->
            NoOps


subscriptions : Model -> Sub Msg
subscriptions _ =
    [ Browser.Events.onKeyDown keyDecoder
    , Time.every 500 (\_ -> NextFrameRequested)
    , Port.toElm |> Sub.map Received
    ]
        |> Sub.batch



-------------------------------
-- VIEW
-------------------------------


view : Model -> Html Msg
view model =
    [ [ (case model.overlay of
            Nothing ->
                Screen.world
                    { frame = model.frame
                    }
                    model.game

            Just Menu ->
                Screen.menu []
                    { frame = model.frame
                    , onClick = Input InputActivate
                    }

            Just GameWon ->
                Screen.gameWon
        )
            |> Layout.el
                ([ Html.Attributes.style "width" "400px"
                 , Html.Attributes.style "height" "400px"
                 ]
                    ++ Layout.centered
                )
      , View.Controls.toHtml
            { onInput = Input
            , item = model.game.item
            , isLevelSelect = model.overlay /= Nothing
            }
      ]
        |> Layout.column
            ([ Html.Attributes.style "width" "400px"
             , Html.Attributes.style "padding" (String.fromInt Config.cellSize ++ "px 0")
             , Layout.gap 16
             ]
                ++ Layout.centered
            )
    ]
        |> Html.div []



-------------------------------
-- MAIN
-------------------------------


main : Program {} Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
