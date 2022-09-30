# ReponoStorage

This library enables simple access to the Repono Storage server.

The Repono Storage server manages it's content in many small container with up to a thousand files
each. The container can be securely encrypted and can only be created if a creation token is known.

This makes the Repono Storage suitable for small projects where the data is self hosted and managed.

## Usage

First you need to create a container. For this you need a creation token with a set storage limit.

```elm
    ReponoStorage.newContainer
        -- The domain name and path to your own Repono Storage.
        "https://my.container.host.local"
        -- The event tag that will be checked in your update function
        ContainerCreatedHandler
        -- The creation token
        "My-creation-token"
        -- The optional password. Set this to `Nothing` for no password at all. Set this to
        -- `Just "password"` to specify a password.
        Nothing
```

After the successful creation you get the `ContainerInfo` with the Id of the new container. This
will be used to create and access any files in it.

To upload a new file to storage you need to call:

```elm
    ReponoStorage.putFile
        -- The domain name and path to your own Repono Storage.
        "https://my.container.host.local"
        -- The event tag that will be checked in your update function
        FileUploaded
        -- The container id
        "container-id"
        -- The file path inside your container. You don't need to check if the directory exists.
        -- This will automatically be managed for you.
        "foo/bar/baz.json"
        -- The password to your container
        Nothing
        -- The content of your file
        (Http.jsonBody jsonContent)
```

To access the content of the file again you need to call:

```elm
    ReponoStorage.getFileJson
        -- The domain name and path to your own Repono Storage.
        "https://my.container.host.local"
        -- The event tag that will be checked in your update function
        MyFileFetched
        -- The container id
        "container-id"
        -- The file path inside your container.
        "foo/bar/baz.json"
        -- The password to your container
        Nothing
        -- the json decoder to read the file contents
        myJsonContentDecoder
```

## Creating a creation token

If you start up the ReponoStorage server it will provide you with a root token that can only be used
to create other tokens. These tokens can be used to create new tokens again or create container.

To create a new token that can be used to create container you have to call:

```elm
    ReponoStorage.newToken
        -- The domain name and path to your own Repono Storage.
        "https://my.container.host.local"
        -- The event tag that will be checked in your update function
        TokenCreated
        -- The root token or another token that can be used to create tokens
        "token-string"
        -- The token limit. This is the number of token and container this token can create. This
        -- value will be reduced from the parent token. The parent token has to have a token limit
        -- that is higher than this number
        1
        -- The storage limit in bytes. This is the maximum storage any container that will be
        -- created from this token can have. This number is not allowed to be higher thant the
        -- storage limit from the parent.
        1000000
        -- An optional hint or comment message
        (Just "my single use token")
```

## Security

It is recommended to connect your storage server using HTTP**S** because the password will be
transmitted in plaintext.
