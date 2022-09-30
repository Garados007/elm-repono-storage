module ReponoStorage exposing
    ( Error(..)
    , ContainerId, ContainerInfo, Container(..), getContainer, newContainer
    , FileId, FilePath, FileInfo, getFile, getFileJson, getFileString, putFile, deleteFile
    , TokenId, TokenInfo, getToken, newToken
    , ReportId, Report, ReportInfo, getReports, postReport
    )

{-| Enables access to the Repono Storage server. These methods and types are simple wrappers over
the REST api.


# Error

@docs Error


# Container

@docs ContainerId, ContainerInfo, Container, getContainer, newContainer


# File

@docs FileId, FilePath, FileInfo, getFile, getFileJson, getFileString, putFile, deleteFile


# Token

@docs TokenId, TokenInfo, getToken, newToken


# Report

@docs ReportId, Report, ReportInfo, getReports, postReport

-}

import Bytes
import Bytes.Decode
import Http
import Iso8601
import Json.Decode as JD exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as JE
import Time exposing (Posix)
import Url


{-| The error states that can happen during the requests.

  - `InvalidPassword`: An invalid password was provided. This error will also returned if no password
    was provided if one was expected or a password was provided if none was expected.
  - `InvalidToken`: The token doesn't meet the criteria. Try to use another one.
  - `NotFound`: A requested object wasn't found. Maybe it was deleted?
  - `StorageLimitReached`: This upload cannot be done because this will conflict with the storage
    limitations. Try to use to delete a file first or use a different container.
  - `TokenExhaused`: The token can no longer be used for this operation.
  - `HttpError`: The returned HTTP error cannot be expressed with one of the above.

-}
type Error
    = HttpError Http.Error
    | InvalidPassword
    | InvalidToken
    | NotFound
    | StorageLimitReached
    | TokenExhaused


{-| An alias for the container id. This is used to make the api more readable.
-}
type alias ContainerId =
    String


{-| Contains the information about the storage container
-}
type alias ContainerInfo =
    { id : ContainerId
    , created : Posix
    , modified : Posix
    , encrypted : Bool
    , storageLimit : Int
    , files : List FileInfo
    }


decodeContainerInfo : Decoder ContainerInfo
decodeContainerInfo =
    JD.succeed ContainerInfo
        |> required "id" JD.string
        |> required "created" Iso8601.decoder
        |> required "modified" Iso8601.decoder
        |> required "encrypted" JD.bool
        |> required "storage_limit" JD.int
        |> required "files" (JD.list decodeFileInfo)


{-| Contains the information of the container information request.

The variant `EncryptedInfo` will be used if the container is encrypted and no password was given
during the request.

-}
type Container
    = FullInfo ContainerInfo
    | EncryptedInfo ContainerId


decodeContainer : Decoder Container
decodeContainer =
    JD.oneOf
        [ JD.map FullInfo decodeContainerInfo
        , JD.map EncryptedInfo <|
            JD.field "id" JD.string
        ]


{-| Returns the information of the container.

**Expected Errors:**

  - `InvalidPassword`: Invalid password for this container. This will also return if the container is
    not encrypted and a password was given.
  - `NotFound`: No container with this id found

-}
getContainer : String -> (Result Error Container -> msg) -> ContainerId -> Maybe String -> Cmd msg
getContainer host mapper id password =
    Http.get
        { url =
            host
                ++ "/v1/container/"
                ++ id
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "?password=" ++ Url.percentEncode pw
                   )
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
                decodeContainer
        }


{-| Create a new container which can store a specific amount of data. For this a token has to be
provided that has a storage limit.

Expected Errors:

  - `InvalidToken`: A container cannot be created. This can be the reason of one of the following:
      - The creation token is expired or does not exists
      - The creation token has no specified storage limit
      - The creation token is exhaused and cannot create more container

-}
newContainer : String -> (Result Error ContainerInfo -> msg) -> TokenId -> Maybe String -> Cmd msg
newContainer host mapper token password =
    Http.get
        { url =
            host
                ++ "/v1/container/?token="
                ++ Url.percentEncode token
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode (String.left 1024 pw)
                   )
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidToken

                                    _ ->
                                        HttpError error
                       )
                )
                decodeContainerInfo
        }


{-| An alias for the file id. This is used to make the api more readable.
-}
type alias FileId =
    String


{-| An alias for the file path. This is used to make the api more readable.
-}
type alias FilePath =
    String


{-| Contains the information about a file inside a container
-}
type alias FileInfo =
    { id : FileId
    , path : FilePath
    , created : Posix
    , modified : Posix
    , size : Int
    , mime : String
    }


decodeFileInfo : Decoder FileInfo
decodeFileInfo =
    JD.succeed FileInfo
        |> required "id" JD.string
        |> required "path" JD.string
        |> required "created" Iso8601.decoder
        |> required "modified" Iso8601.decoder
        |> required "size" JD.int
        |> required "mime" JD.string


{-| Get the binary content of a file.

Expected Errors:

  - `InvalidPassword`: The password is wrong or not provided (if required).
  - `NotFound`: The file or container not found.

-}
getFile :
    String
    -> (Result Error a -> msg)
    -> ContainerId
    -> FilePath
    -> Maybe String
    -> Bytes.Decode.Decoder a
    -> Cmd msg
getFile host mapper containerId filePath password decoder =
    Http.get
        { url =
            host
                ++ "/v1/file/"
                ++ containerId
                ++ "?path="
                ++ Url.percentEncode filePath
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , expect =
            Http.expectBytes
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
                decoder
        }


{-| Get the json content of a file.

Expected Errors:

  - `InvalidPassword`: The password is wrong or not provided (if required).
  - `NotFound`: The file or container not found.

-}
getFileJson :
    String
    -> (Result Error a -> msg)
    -> ContainerId
    -> FilePath
    -> Maybe String
    -> Decoder a
    -> Cmd msg
getFileJson host mapper containerId filePath password decoder =
    Http.get
        { url =
            host
                ++ "/v1/file/"
                ++ containerId
                ++ "?path="
                ++ Url.percentEncode filePath
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
                decoder
        }


{-| Get the text content of a file.

Expected Errors:

  - `InvalidPassword`: The password is wrong or not provided (if required).
  - `NotFound`: The file or container not found.

-}
getFileString :
    String
    -> (Result Error String -> msg)
    -> ContainerId
    -> FilePath
    -> Maybe String
    -> Cmd msg
getFileString host mapper containerId filePath password =
    Http.get
        { url =
            host
                ++ "/v1/file/"
                ++ containerId
                ++ "?path="
                ++ Url.percentEncode filePath
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , expect =
            Http.expectString
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
        }


{-| Replace or upload the new content of a file.

**Limitations:**

  - The given file path exceed the maximum length of 1024 bytes.
  - The new file size won't make the total size of the container larger than it's maximum allowence.
  - File sizes smaller than 1024 bytes will be counted as they will use 1024 bytes.
  - Each container can have a maximum of 1024 files. After that adding new files to the container is
    not allowed until some are deleted.

**Expected Errors:**

  - `InvalidPassword`: The password is wrong or not provided (if required).
  - `NotFound`: File not found.
  - `StorageLimitReached`: Replacing or adding this file will make the container larger than its
    allowed to be. This code will also returned if the provided path is larger than 1024 bytes.

-}
putFile :
    String
    -> (Result Error () -> msg)
    -> ContainerId
    -> FilePath
    -> Maybe String
    -> Http.Body
    -> Cmd msg
putFile host mapper containerId filePath password content =
    Http.request
        { method = "PUT"
        , headers = []
        , url =
            host
                ++ "/v1/file/"
                ++ containerId
                ++ "?path="
                ++ Url.percentEncode filePath
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , body = content
        , expect =
            Http.expectWhatever
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    Http.BadStatus 507 ->
                                        StorageLimitReached

                                    _ ->
                                        HttpError error
                       )
                )
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Deletes a stored file.

**Expected Errors:**

  - `InvalidPassword`: The password is wrong or not provided (if required).
  - `NotFound`: File not found.

-}
deleteFile :
    String
    -> (Result Error () -> msg)
    -> ContainerId
    -> FilePath
    -> Maybe String
    -> Cmd msg
deleteFile host mapper containerId filePath password =
    Http.request
        { method = "DELETE"
        , headers = []
        , url =
            host
                ++ "/v1/file/"
                ++ containerId
                ++ "?path="
                ++ Url.percentEncode filePath
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , body = Http.emptyBody
        , expect =
            Http.expectWhatever
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
        , timeout = Nothing
        , tracker = Nothing
        }


{-| An alias for the token id. This is used to make the api more readable.
-}
type alias TokenId =
    String


{-| Contains the information about a token that can be used to create container.

  - `id`: The id of this token
  - `parent`: The parent token id
  - `childTokens`: The direct child tokens
  - `childContainer`: The container that are created with this token
  - `storageLimit`: The maximum storage limit for subsequent containers and tokens. If this field is
    null than this token has an unlimited storage capacity and cannot be used to create containers
    directly.
  - `tokenLimit`: The remaining number of tokens that can be created with this one. Only the root
    token can have an unlimited number of null.
  - `expired`: States if this token is expired and can be used to create more tokens and containers.
  - `created`: The creation date of this token.
  - `used`: The last date this token was used.
  - `hint`: The hint that was provided durring creation

-}
type alias TokenInfo =
    { id : TokenId
    , parent : Maybe TokenId
    , childTokens : List TokenId
    , childContainer : List ContainerId
    , storageLimit : Maybe Int
    , tokenLimit : Maybe Int
    , expired : Bool
    , created : Posix
    , used : Posix
    , hint : Maybe String
    }


decodeTokenInfo : Decoder TokenInfo
decodeTokenInfo =
    JD.succeed TokenInfo
        |> required "id" JD.string
        |> required "parent" (JD.nullable JD.string)
        |> required "child_tokens" (JD.list JD.string)
        |> required "child_container" (JD.list JD.string)
        |> required "storage_limit" (JD.nullable JD.int)
        |> required "token_limit" (JD.nullable JD.int)
        |> required "expired" JD.bool
        |> required "created" Iso8601.decoder
        |> required "used" Iso8601.decoder
        |> required "hint" (JD.nullable JD.string)


{-| Returns the information of the Token

**Expected Errors:**

  - `NotFound`: No token with this id found

-}
getToken : String -> (Result Error TokenInfo -> msg) -> TokenId -> Cmd msg
getToken host mapper id =
    Http.get
        { url = host ++ "/v1/token/" ++ id
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
                decodeTokenInfo
        }


{-| Creates a new token. The new token is a child of the parent token.

**Expected Errors:**

  - `NotFound`: No parent token with this id found
  - `TokenExhaused`: The parent token cannot create a new child token. That can be the reason
    of:
      - parent token has no remaining tokens to create (token limit is 0).
      - parent token is expired
      - requested storage limit is larger than the storage limit of the header token
      - requested token limit is larger than the token limit of the header token

-}
newToken :
    String
    -> (Result Error TokenInfo -> msg)
    -> TokenId
    -> Int
    -> Int
    -> Maybe String
    -> Cmd msg
newToken host mapper parent tokenLimit storageLimit hint =
    Http.get
        { url =
            host
                ++ "/v1/token/"
                ++ parent
                ++ "/new?token_limit="
                ++ String.fromInt tokenLimit
                ++ "&storage_limit="
                ++ String.fromInt storageLimit
                ++ (case hint of
                        Nothing ->
                            ""

                        Just ht ->
                            "&hint=" ++ Url.percentEncode ht
                   )
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 404 ->
                                        NotFound

                                    Http.BadStatus 507 ->
                                        TokenExhaused

                                    _ ->
                                        HttpError error
                       )
                )
                decodeTokenInfo
        }


{-| An alias for the report id. This is used to make the api more readable.
-}
type alias ReportId =
    String


{-| The information of a single report that was submitted.
-}
type alias Report =
    { reason : String
    , files : List FilePath
    }


decodeReport : Decoder Report
decodeReport =
    JD.succeed Report
        |> required "reason" JD.string
        |> Json.Decode.Pipeline.optional "files" (JD.list JD.string) []


encodeReport : Report -> JE.Value
encodeReport report =
    JE.object
        [ Tuple.pair "reason" <| JE.string report.reason
        , Tuple.pair "files" <|
            JE.list JE.string report.files
        ]


{-| The stored meta information including the full report that was submitted.
-}
type alias ReportInfo =
    { id : ReportId
    , containerId : ContainerId
    , created : Posix
    , report : Report
    }


decodeReportInfo : Decoder ReportInfo
decodeReportInfo =
    JD.succeed ReportInfo
        |> required "id" JD.string
        |> required "container_id" JD.string
        |> required "created" Iso8601.decoder
        |> required "report" decodeReport


{-| Search for open reports. These reports can be limited to a specific container or file that
should be contained.

**Expected Errors:** _none_

-}
getReports :
    String
    -> (Result Error (List ReportInfo) -> msg)
    -> Maybe ContainerId
    -> Maybe FilePath
    -> Cmd msg
getReports host mapper containerId path =
    Http.get
        { url =
            host
                ++ "/v1/report/?"
                ++ (String.concat <|
                        List.intersperse "&" <|
                            List.filterMap
                                (\( a, b ) ->
                                    Maybe.map
                                        (\x -> a ++ "=" ++ Url.percentEncode x)
                                        b
                                )
                                [ ( "container_id", containerId )
                                , ( "path", path )
                                ]
                   )
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 404 ->
                                        NotFound

                                    Http.BadStatus 507 ->
                                        TokenExhaused

                                    _ ->
                                        HttpError error
                       )
                )
                (JD.list decodeReportInfo)
        }


{-| Creates a new report for a container. This report will be stored and will be checked by a
moderator. If a report is accepted the corresponding files or container will be deleted. After a
report is solved (successful or not) they will be removed from the list.

If is possible to block creation tokens because of reports.

If the container is password protected it is required to add the correct password. This password
will be stored in clear text on the server until the report is resolved.

**Expected Errors:**

  - `InvalidPassword`: Invalid password for the container
  - `NotFound`: Container not found

-}
postReport :
    String
    -> (Result Error ReportInfo -> msg)
    -> ContainerId
    -> Maybe String
    -> Report
    -> Cmd msg
postReport host mapper containerId password report =
    Http.post
        { url =
            host
                ++ "/v1/report/?container="
                ++ Url.percentEncode containerId
                ++ (case password of
                        Nothing ->
                            ""

                        Just pw ->
                            "&password=" ++ Url.percentEncode pw
                   )
        , body = Http.jsonBody <| encodeReport report
        , expect =
            Http.expectJson
                (mapper
                    << (Result.mapError <|
                            \error ->
                                case error of
                                    Http.BadStatus 403 ->
                                        InvalidPassword

                                    Http.BadStatus 404 ->
                                        NotFound

                                    _ ->
                                        HttpError error
                       )
                )
                decodeReportInfo
        }
