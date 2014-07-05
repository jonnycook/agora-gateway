serverProcessId = new Date().getTime()
serverId = 1

env = null
if process.argv[2]
	env = require './env.test'
else
	env = require './env'

if env.logErrors
	winston = require('winston')
	winston.add winston.transports.File, filename: "errors_#{serverProcessId}.log", json:false, handleExceptions:true


mysql = require 'mysql'
_ = require 'lodash'
express = require 'express'
bodyParser = require 'body-parser'
request = require 'request'
require 'colors'
require('source-map-support').install();
MongoClient = require('mongodb').MongoClient

mongoDb = null
processLogsCol = null
clientIdsByServerId = {}
clientsIdsForUserId = {}


{parse:parse} = require './utils'

connection = mysql.createConnection env.db
connection.connect()

app = express()
app.use bodyParser limit:'50mb'
app.listen env.httpPort

userIdsByClientId = {}
userIdForClientId = (clientId, cb) ->
	if userIdsByClientId[clientId]
		cb userIdsByClientId[clientId]
	else
		connection.query "SELECT user_id FROM clients WHERE client_id = '#{clientId}'", (error, rows, fields) ->
			userIdsByClientId[clientId] = parseInt rows[0].user_id
			data = {}
			data["clients.#{clientId}"] = userIdsByClientId[clientId]
			mongoDb.collection('snapshots').update {_id:serverProcessId}, '$set':data, ->
			cb userIdsByClientId[clientId]

User = require('./User') env, userIdForClientId, connection

app.get '/debug', (req, res) ->
	console.log '====DEBUG===='
	userId = req.query.userId
	user = User.user userId

	console.log '=user.subscribers='
	console.log user.subscribers
	console.log '=user.outline='
	console.log user.outline
	console.log '=user.shared='
	console.log user.shared
	console.log '=User.clientSubscriptions='
	console.log User.clientSubscriptions
	console.log '=clientIdsByServerId='
	console.log clientIdsByServerId
	res.send ''

app.get '/sync', (req, res) ->
	userId = req.query.userId
	user = User.user userId
	user.syncClients()
	res.send ''

resolveUserId = (user, params, cb) ->
	if params.clientId == 'Carl Sagan'
		cb params.userId
	else
		userIdForClientId params.clientId, (userId) ->
			if userId == parseInt params.userId
				cb userId
			else
				cb null

commands = 
	init: (user, params, sendResponse) ->
		clientIdsByServerId[params.serverId] ?= {}
		clientIdsByServerId[params.serverId][params.clientId] = true
		user.hasPermissions params.clientId, 'init', (permission) ->
			if permission
				user.addSubscriber params.clientId, '*'
				user.data '*', (data) ->
					sendResponse data
			else
				sendResponse 'not allowed'

	'share/create': (user, params, sendResponse) ->
		resolveUserId user, params, (userId) ->
			if userId
				request
					url: "http://#{env.getUpdateServer()}/shared/create.php?userId=#{userId}",
					method: 'post'
					form: params,
					(err, response, body) ->
						console.log body
		sendResponse()

	'share/delete': (user, params, sendResponse) ->
		resolveUserId user, params, (userId) ->
			# console.log 'hahah', userId
			if userId
				request
					url: "http://#{env.getUpdateServer()}/shared/delete.php?userId=#{userId}",
					method: 'post'
					form: params
		sendResponse()

	'share/update': (user, params, sendResponse) ->
		resolveUserId user, params, (userId) ->
			if userId
				request
					url: "http://#{env.getUpdateServer()}/shared/update.php?userId=#{userId}",
					method: 'post'
					form: params
		sendResponse()

	shared: (user, params, sendResponse) ->
		record = params.record
		action = params.action
		if user.subscribers?['*']
			changes = shared_objects:{}
			if action == 'create'
				if user.shared && parseInt(record.user_id) == user.id
					if !user.shared[record.object]
						user.shared[record.object] = []
					user.shared[record.object].push parseInt record.with_user_id

				changes.shared_objects['G' + record.id] =
					user_id:'G' + record.user_id
					title:record.title
					with_user_id:'G' + record.with_user_id
					object:record.object
					user_name:record.user_name
					with_user_name:record.with_user_name
			if action == 'update'
				changes.shared_objects['G' + record.id] =
					title:record.title
			else if action == 'delete'
				if record.with_user_id
					withUserId = parseInt record.with_user_id
					if user.shared
						if user.shared[record.object]
							_.pull user.shared[record.object], withUserId
							if !user.shared[record.object].length
								delete user.shared[record.object]

					clientIds = clientsIdsForUserId[withUserId]
					if clientIds
						for clientId in clientIds
							user.removeSubscriber clientId, record.object

				changes.shared_objects['G' + record.id] = 'deleted'

			user.sendUpdate changes, '*'

		sendResponse 'ok'

	collaborators: (user, params, sendResponse) ->
		user.sendUpdate params.changes, '*'
		if params.object
			user.sendUpdate params.changes, params.object
		sendResponse 'ok'

	update: (user, params, sendResponse) ->
		user.hasPermissions params.clientId, 'update', parse(params.changes), (permission) ->
			if permission
				user.update params.clientId, params.updateToken, params.changes, (response) ->
					sendResponse response
			else
				sendResponse 'not allowed'

	subscribe: (user, params, sendResponse) ->
		clientIdsByServerId[params.serverId] ?= {}
		clientIdsByServerId[params.serverId][params.clientId] = true

		user.hasPermissions params.clientId, 'subscribe', params.object, params.key, (permission) ->
			if permission
				userIdForClientId params.clientId, (userId) ->
					clientsIdsForUserId[userId] ?= []
					if !(params.clientId in clientsIdsForUserId[userId])
						clientsIdsForUserId[userId].push params.clientId
					user.addSubscriber params.clientId, params.object
					user.data params.object, (data) ->
						sendResponse data
			else
				sendResponse 'not allowed'

	unsubscribe: (user, params, sendResponse) ->
		clientId = params.clientId
		user.removeSubscriber clientId, params.object
		sendResponse ''

	unsubscribeClient: (params, sendResponse) ->
		clientId = params.clientId
		if User.clientSubscriptions[clientId]
			subscriptions = _.cloneDeep User.clientSubscriptions[clientId]
			for userId, objects of subscriptions
				user = User.user userId
				for object in objects
					user.removeSubscriber clientId, object
		sendResponse ''

	retrieve: (params, sendResponse) ->
		request {
			url: "http://#{env.getUpdateServer()}/retrieve.php?clientId=#{params.clientId}",
			method: 'post'
			form:
				toRetrieve:params.records
		}, (err, response, body) ->
			sendResponse body

executeCommand = (type, params, sendResponse) ->
	console.log 'command', type, params
	if env.log
		timestamp = new Date().getTime()
		processLogsCol.insert {timestamp:timestamp, type:type, params:JSON.stringify params}, ->

	if params.userId && commands[type].length == 3
		User.operate params.userId, (user) ->
			commands[type] user, params, (response) ->
				sendResponse response
				user.done()
	else
		commands[type] params, sendResponse


start = ->
	console.log 'started'

	for commandName, __ of commands
		do (commandName) ->
			app.post "/#{commandName}", (req, res) ->
				executeCommand commandName, req.body, (response) -> res.send response

	app.post '/port/started', (req, res) ->
		if clientIdsByServerId[req.body.serverId]
			clientIds = clientIdsByServerId[req.body.serverId]
			for clientId,__ of clientIds
				subscriptions = _.cloneDeep User.clientSubscriptions[clientId]
				for userId, objects of subscriptions
					user = User.user userId
					for object in objects
						user.removeSubscriber clientId, object
			delete clientIdsByServerId[req.body.serverId]
		res.send 'ok'


if process.argv[2]
	if process.argv[2] == 'tests'

	else
		snapshot = process.argv[2]
		start()

		request {
			url: "http://#{env.getUpdateServer()}/restoreSnapshot.php?id=#{snapshot}",
			method: 'get'
		}, ->
			MongoClient.connect env.mongoDb, (err, db) ->
				mongoDb = db
				processLogsCol = mongoDb.collection "processLogs_#{snapshot}"
				cursor = processLogsCol.find()
				cursor.toArray (err, docs) ->
					current = 0
					next = ->
						if current < docs.length
							doc = docs[current++]
							params = JSON.parse doc.params
							type = doc.type
							console.log '>', type, params

							if params.userId && commands[type].length == 3
								User.operate params.userId, (user) ->
									commands[type] user, params, (response) ->
										console.log '< %s'.blue, response
										user.done()
										next()
							else
								commands[type] params, (response) ->
									console.log '< %s'.blue, response
									next()
						else
							console.log 'done'
					next()
else
	request {
		method:'get'
		url: "http://#{env.getUpdateServer()}/saveSnapshot.php?id=#{serverProcessId}"
	}, (error, response, body) =>
		env.init ->
			MongoClient.connect env.mongoDb, (err, db) ->
				mongoDb = db
				processLogsCol = mongoDb.collection "processLogs_#{serverProcessId}"

				count = 0
				for portServer in env.portServers
					request {
						url: "http://#{portServer}/gateway/started",
						method:'post'
						form:
							serverId:serverId
					}, (error) ->
						console.log 'has error', error if error
						if ++count == env.portServers.length
							start()
