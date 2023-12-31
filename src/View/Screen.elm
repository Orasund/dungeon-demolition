module View.Screen exposing (gameWon, menu, world)

import Config
import Dict
import Entity exposing (Enemy(..), Entity(..))
import Game exposing (Game)
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Keyed
import Html.Style
import Image
import Layout
import Position
import View.Cell


gameWon : Html msg
gameWon =
    [ "Thanks for playing"
        |> Layout.text
            [ Html.Attributes.style "font-size" "46px"
            , Layout.contentCentered
            ]
    ]
        |> Layout.column
            ([ Html.Attributes.class "dark-background"
             , Html.Style.width "400px"
             , Html.Style.height "400px"
             , Html.Attributes.style "color" "white"
             ]
                ++ Layout.centered
            )


menu : List (Attribute msg) -> { frame : Int, onClick : msg } -> Html msg
menu attrs args =
    [ [ Image.image
            [ Image.pixelated
            , Layout.contentCentered
            ]
            { url = "assets/logo.png"
            , width = 39 * 8
            , height = 19 * 8
            }
      ]
        |> Layout.column
            [ Html.Attributes.style "color" "white"
            , Layout.gap 32
            ]

    --, logo args.frame
    ]
        |> Layout.column
            ([ Html.Attributes.class "dark-background"
             , Html.Style.width "400px"
             , Html.Style.height "400px"
             ]
                ++ Layout.asButton
                    { label = "Next Level"
                    , onPress = Just args.onClick
                    }
                ++ attrs
                ++ Layout.centered
            )


world :
    { frame : Int
    }
    -> Game
    -> Html msg
world args game =
    (Position.asGrid
        { rows = Config.roomSize
        , columns = Config.roomSize
        }
        |> List.map
            (\( x, y ) ->
                ( "0_" ++ String.fromInt x ++ "_" ++ String.fromInt y
                , [ if game.floor |> Dict.member ( x, y ) then
                        View.Cell.floor
                            [ Html.Style.positionAbsolute
                            , Html.Style.top "0"
                            ]

                    else if game.floor |> Dict.member ( x, y - 1 ) then
                        View.Cell.holeTop
                            [ Html.Style.positionAbsolute
                            , Html.Style.top "0"
                            ]

                    else
                        View.Cell.hole
                            [ Html.Style.positionAbsolute
                            , Html.Style.top "0"
                            ]
                  , game.items
                        |> Dict.get ( x, y )
                        |> Maybe.map
                            (\item ->
                                View.Cell.item
                                    [ Html.Style.positionAbsolute
                                    , Html.Style.top "0"
                                    ]
                                    item
                            )
                        |> Maybe.withDefault Layout.none
                  , game.particles
                        |> Dict.get ( x, y )
                        |> Maybe.map
                            (\particle ->
                                View.Cell.particle
                                    [ Html.Style.positionAbsolute
                                    , Html.Style.top "0"
                                    ]
                                    particle
                            )
                        |> Maybe.withDefault Layout.none
                  ]
                    ++ (if game.floor |> Dict.member ( x, y ) |> not then
                            View.Cell.borders ( x, y ) game

                        else
                            []
                       )
                    |> Html.div
                        [ Html.Style.positionAbsolute
                        , Html.Attributes.style "left"
                            (String.fromFloat (Config.cellSize * toFloat x) ++ "px")
                        , Html.Attributes.style "top"
                            (String.fromFloat (Config.cellSize * toFloat y) ++ "px")
                        ]
                )
            )
    )
        ++ (game.cells
                |> Dict.toList
                |> List.map
                    (\( ( x, y ), cell ) ->
                        ( "1_" ++ String.fromInt cell.id
                        , View.Cell.toHtml
                            [ Html.Attributes.style "position" "absolute"
                            , Html.Attributes.style "left"
                                (String.fromFloat (Config.cellSize * toFloat x) ++ "px")
                            , Html.Attributes.style "top"
                                (String.fromFloat (Config.cellSize * toFloat y) ++ "px")
                            , Html.Attributes.style "transition" "left 0.2s,top 0.2s"
                            ]
                            { frame = args.frame
                            , playerDirection = game.playerDirection
                            }
                            cell.entity
                        )
                    )
           )
        |> List.sortBy Tuple.first
        |> Html.Keyed.node "div"
            [ Html.Attributes.style "position" "relative"
            , Html.Attributes.style "width" (String.fromFloat (Config.cellSize * toFloat Config.roomSize) ++ "px")
            , Html.Attributes.style "height" (String.fromFloat (Config.cellSize * toFloat Config.roomSize) ++ "px")
            , Html.Attributes.style "border" "4px solid white"
            ]
