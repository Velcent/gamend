#!/usr/bin/env node
/**
 * check_js.js
 *
 * Call a live server through the built JS SDK and check each answer is an
 * instance of its named model class (`SessionResponse`, `Lobby`, `GroupPage`
 * ...). smoke_package.js proves the package loads; this proves the document
 * and the server agree. It found the operations whose missing `security`
 * kept the SDK from sending its token.
 *
 *   node clients/check_js.js http://127.0.0.1:4000
 *
 * Signs in with a fresh device id (device login must be on) and writes a
 * user, a lobby and a party it leaves, and a group it keeps.
 */
const path = require('path')
const sdk = require(path.join(__dirname, 'javascript', 'dist', 'index.js'))
const client = new sdk.ApiClient()
client.basePath = process.argv[2] || 'http://127.0.0.1:4000'
let failures = 0
function expect (label, value, Model) {
  if (value instanceof Model) console.log(`ok   ${label} -> ${Model.name}`)
  else { failures++; console.log(`FAIL ${label}: got ${JSON.stringify(value).slice(0, 120)}`) }
  return value
}
;(async () => {
  const auth = new sdk.AuthenticationApi(client)
  const session = expect('deviceLogin', await auth.deviceLogin({ deviceLoginRequest: { device_id: `js-check-${Date.now()}` } }), sdk.SessionResponse)
  expect('deviceLogin.data', session.data, sdk.Session)
  client.authentications.authorization.accessToken = session.data.access_token
  const me = expect('getCurrentUser', await new sdk.UsersApi(client).getCurrentUser(), sdk.CurrentUser)
  expect('getCurrentUser.linked_providers', me.linked_providers, sdk.LinkedProviders)
  const lobbies = new sdk.LobbiesApi(client)
  const lobby = expect('quickJoin', await lobbies.quickJoin({ quickJoinRequest: { title: 'js-check', max_users: 2 } }), sdk.Lobby)
  const detail = expect('getLobby', await lobbies.getLobby(lobby.id), sdk.LobbyResponse)
  expect('getLobby.data', detail.data, sdk.Lobby)
  expect('getLobby.members[0]', detail.members[0], sdk.UserBrief)
  const page = expect('listLobbies', await lobbies.listLobbies({}), sdk.LobbyPage)
  expect('listLobbies.meta', page.meta, sdk.PageMeta)
  expect('listFriends', await new sdk.FriendsApi(client).listFriends({}), sdk.FriendPage)
  await lobbies.leaveLobby()
  const groups = new sdk.GroupsApi(client)
  const group = expect('createGroup', await groups.createGroup({ createGroupRequest: { title: `js-check-${Date.now()}` } }), sdk.Group)
  expect('listGroupMembers', await groups.listGroupMembers(group.id, {}), sdk.GroupMemberPage)
  expect('getGroup', await groups.getGroup(group.id), sdk.Group)
  const party = expect('createParty', await new sdk.PartiesApi(client).createParty({ createPartyRequest: { max_size: 4 } }), sdk.Party)
  expect('createParty.members[0]', party.members[0], sdk.UserBrief)
  await new sdk.PartiesApi(client).leaveParty()
  console.log(`failures=${failures}`)
  process.exit(failures ? 1 : 0)
})().catch(e => { console.log('FAIL', e.message, e.response && e.response.text); process.exit(1) })
