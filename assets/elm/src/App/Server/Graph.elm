module App.Server.Graph exposing
    ( connect
    , connectUrl
    , decodeConnection
    , decodeCotonomaKeyField
    , decodeGraph
    , disconnect
    , fetchGraph
    , fetchSubgraph
    , fetchSubgraphIfCotonoma
    , pinCotos
    , pinUrl
    , reorder
    , unpinCoto
    )

import App.Messages exposing (Msg(..))
import App.Server.Coto
import App.Types.Connection exposing (Connection, Direction)
import App.Types.Coto exposing (Coto, CotoId, Cotonoma, CotonomaKey)
import App.Types.Graph exposing (Graph)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Task exposing (Task, andThen)
import Utils.HttpUtil exposing (ClientId, httpDelete, httpPut)


decodeConnection : Decode.Decoder Connection
decodeConnection =
    Decode.map4 Connection
        (Decode.maybe (Decode.field "start" Decode.string))
        (Decode.field "end" Decode.string)
        (Decode.maybe (Decode.field "linking_phrase" Decode.string))
        (Decode.field "created_by" Decode.string)


decodeCotonomaKeyField : Decode.Decoder (Maybe String)
decodeCotonomaKeyField =
    Decode.maybe (Decode.field "cotonoma_key" Decode.string)


decodeGraph : Decode.Decoder Graph
decodeGraph =
    Decode.map3 App.Types.Graph.initGraph
        (Decode.field "cotos" (Decode.dict App.Server.Coto.decodeCoto))
        (Decode.field "root_connections" (Decode.list decodeConnection))
        (Decode.field "connections" (Decode.dict <| Decode.list decodeConnection))


fetchGraph : Maybe CotonomaKey -> Cmd Msg
fetchGraph maybeCotonomaKey =
    let
        url =
            maybeCotonomaKey
                |> Maybe.map (\key -> "/api/graph/" ++ key)
                |> Maybe.withDefault "/api/graph"
    in
    Http.send GraphFetched (Http.get url decodeGraph)


fetchSubgraph : CotonomaKey -> Cmd Msg
fetchSubgraph cotonomaKey =
    Http.send
        SubgraphFetched
        (Http.get ("/api/graph/subgraph/" ++ cotonomaKey) decodeGraph)


fetchSubgraphIfCotonoma : Graph -> CotoId -> Cmd Msg
fetchSubgraphIfCotonoma graph cotoId =
    graph
        |> App.Types.Graph.getCoto cotoId
        |> Maybe.andThen (\coto -> coto.asCotonoma)
        |> Maybe.map (\cotonoma -> cotonoma.key)
        |> Maybe.map fetchSubgraph
        |> Maybe.withDefault Cmd.none


pinUrl : Maybe CotonomaKey -> String
pinUrl maybeCotonomaKey =
    maybeCotonomaKey
        |> Maybe.map (\key -> "/api/graph/" ++ key ++ "/pin")
        |> Maybe.withDefault "/api/graph/pin"


connectingParamsAsBody : String -> List CotoId -> Maybe String -> Http.Body
connectingParamsAsBody key targetIds linkingPhrase =
    Encode.object
        [ ( key
          , targetIds
                |> List.map Encode.string
                |> Encode.list
          )
        , ( "linking_phrase"
          , linkingPhrase
                |> Maybe.map Encode.string
                |> Maybe.withDefault Encode.null
          )
        ]
        |> Http.jsonBody


pinCotos : ClientId -> Maybe CotonomaKey -> List CotoId -> Cmd Msg
pinCotos clientId maybeCotonomaKey cotoIds =
    let
        url =
            pinUrl maybeCotonomaKey

        body =
            connectingParamsAsBody "coto_ids" cotoIds Nothing
    in
    httpPut url clientId body (Decode.succeed "done")
        |> Http.send CotoPinned


unpinCoto : ClientId -> Maybe CotonomaKey -> CotoId -> Cmd Msg
unpinCoto clientId maybeCotonomaKey cotoId =
    let
        url =
            pinUrl maybeCotonomaKey ++ "/" ++ cotoId
    in
    httpDelete url clientId |> Http.send CotoUnpinned


connectUrl : Maybe CotonomaKey -> CotoId -> String
connectUrl maybeCotonomaKey startId =
    maybeCotonomaKey
        |> Maybe.map (\key -> "/api/graph/" ++ key ++ "/connection/" ++ startId)
        |> Maybe.withDefault ("/api/graph/connection/" ++ startId)


makeConnectTask :
    ClientId
    -> Maybe CotonomaKey
    -> CotoId
    -> List CotoId
    -> Direction
    -> Maybe String
    -> Task Http.Error (List String)
makeConnectTask clientId maybeCotonomaKey subject objects direction linkingPhrase =
    let
        requests =
            case direction of
                App.Types.Connection.Outbound ->
                    [ httpPut
                        (connectUrl maybeCotonomaKey subject)
                        clientId
                        (connectingParamsAsBody "end_ids" objects linkingPhrase)
                        (Decode.succeed "done")
                    ]

                App.Types.Connection.Inbound ->
                    List.map
                        (\startId ->
                            httpPut
                                (connectUrl maybeCotonomaKey startId)
                                clientId
                                (connectingParamsAsBody "end_ids" [ subject ] linkingPhrase)
                                (Decode.succeed "done")
                        )
                        objects
    in
    requests |> List.map Http.toTask |> Task.sequence


connect :
    ClientId
    -> Maybe CotonomaKey
    -> CotoId
    -> List CotoId
    -> Direction
    -> Maybe String
    -> Cmd Msg
connect clientId maybeCotonomaKey subject objects direction linkingPhrase =
    makeConnectTask clientId maybeCotonomaKey subject objects direction linkingPhrase
        |> Task.attempt Connected


disconnect : ClientId -> CotoId -> CotoId -> Cmd Msg
disconnect clientId startId endId =
    let
        url =
            "/api/graph/connection/" ++ startId ++ "/" ++ endId
    in
    httpDelete url clientId
        |> Http.send ConnectionDeleted


reorder :
    (Result Http.Error String -> msg)
    -> ClientId
    -> Maybe CotonomaKey
    -> Maybe CotoId
    -> List CotoId
    -> Cmd msg
reorder tag clientId maybeCotonomaKey maybeStartId endIds =
    let
        url =
            maybeStartId
                |> Maybe.map
                    (\startId ->
                        "/api/graph/connection/" ++ startId ++ "/reorder"
                    )
                |> Maybe.withDefault
                    (maybeCotonomaKey
                        |> Maybe.map
                            (\cotonomaKey ->
                                "/api/graph/" ++ cotonomaKey ++ "/reorder"
                            )
                        |> Maybe.withDefault "/api/graph/reorder"
                    )

        body =
            Encode.object
                [ ( "end_ids", endIds |> List.map Encode.string |> Encode.list ) ]
                |> Http.jsonBody
    in
    httpPut url clientId body (Decode.succeed "done") |> Http.send tag
