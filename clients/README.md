# Generate Clients

To generate the Godot client, simply run:

```sh
./generate_godot.sh
```

It runs openapi-generator in Docker. Without Docker, point it at a local
openapi-generator-cli jar instead:

```sh
OPENAPI_GENERATOR_JAR=/path/to/openapi-generator-cli.jar ./generate_godot.sh
```

Then check it in a headless Godot 4 (`GODOT_BIN`, or `godot` on PATH): every
addon script must compile, and with a server URL a set of live calls must land
in their named model classes (`GamendLobby`, `GamendSession`, …):

```sh
./check_godot.sh
./check_godot.sh http://127.0.0.1:4000
```

To generate the Javascript client, simply run:

```sh
npm run openapi
npm run generate
```

and check it against a running server: every call must answer with its named
model class (`Lobby`, `SessionResponse`, …):

```sh
node check_js.js http://127.0.0.1:4000
```
