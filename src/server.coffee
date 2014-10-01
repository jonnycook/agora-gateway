serverProcessId = new Date().getTime()

domain = require 'domain'

# domain.create().on('error', -> console.log 'poop').run -> throw new Error()
# process.exit()


env = null
if process.argv[2]
	env = require './env.test'
else
	env = require './env'

serverId = env.serverId


# if env.logErrors
# 	winston = require('winston')
# 	winston.add winston.transports.File, filename: "errors_#{serverProcessId}.log", json:false, handleExceptions:true

portForClient = (clientId) -> 
	if routerIdForClientId[clientId]
		portServers[routerIdForClientId[clientId]]
	else
		throw new Error "no router id for #{clientId}"

portServers = null
if env.portServers
	portServers = env.portServers
else
	portServers =
		1:'66.228.50.174:3001'
		2:'23.239.24.188:3001'

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
clientIdsByRouterId = {}
clientsIdsForUserId = {}

routerIdForClientId = {}

{parse:parse} = require './utils'

connection = mysql.createConnection env.db
connection.connect()

app = express()
app.use bodyParser limit:'50mb'
app.listen env.httpPort

usersByClientId = {}
userIdForClientId = (clientId, cb) ->
	if usersByClientId[clientId]
		cb usersByClientId[clientId].id
	else
		connection.query "SELECT user_id, subscribes FROM clients WHERE client_id = '#{clientId}'", (error, rows, fields) ->
			if rows.length
				usersByClientId[clientId] =
					subscribes:parseInt rows[0].subscribes
					id:parseInt rows[0].user_id

				# data = {}
				# data["clients.#{clientId}"] = usersByClientId[clientId]
				# mongoDb.collection('snapshots').update {_id:serverProcessId}, '$set':data, ->
				cb usersByClientId[clientId].id
			else
				cb null

User = require('./User') env, userIdForClientId, connection, portForClient

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
	console.log '=user.sharedBySubscribeObject='
	console.log user.sharedBySubscribeObject
	console.log '=user.permissions='
	console.log user.permissions
	console.log '=User.clientSubscriptions='
	console.log User.clientSubscriptions
	console.log '=clientIdsByRouterId='
	console.log clientIdsByRouterId
	console.log '=routerIdForClientId='
	console.log routerIdForClientId
	res.send ''

app.get '/sync', (req, res) ->
	userId = req.query.userId
	user = User.user userId
	user.syncClients()
	res.send ''

validate = (args..., success, fail) ->
	results = []
	for i in [0...args.length/2]
		value = args[i]
		type = args[i + 1]


		switch type
			when 'json'
				result = parse value
				if result instanceof Error
					fail()
					return
				else
					results[i] = result
	success results...


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
	error: ->
		throw new Error()

	track: (params, sendResponse) ->
		request
			url: "http://#{env.getUpdateServer()}/track.php?clientId=#{params.clientId}",
			method: 'post'
			form: args:params.args,
			(err, response, body) ->
				console.log body
		sendResponse()

	init: (user, params, sendResponse) ->
		if params.serverId
			clientIdsByRouterId[params.serverId] ?= {}
			clientIdsByRouterId[params.serverId][params.clientId] = true
			routerIdForClientId[params.clientId] = params.serverId

		user.hasPermissions params.clientId, 'init', (permission) ->
			if permission
				if usersByClientId[params.clientId].subscribes
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
				if parseInt(record.user_id) == user.id
					user.addShared record.object, record.subscribe_object, record.with_user_id, record.role

				changes.shared_objects['G' + record.id] =
					user_id:'G' + record.user_id
					title:record.title
					with_user_id:'G' + record.with_user_id
					object:record.object
					subscribe_object:record.subscribe_object
					user_name:record.user_name
					with_user_name:record.with_user_name
					role:record.role

			if action == 'update'
				changes.shared_objects['G' + record.id] =
					title:record.title
			else if action == 'delete'
				if record.with_user_id
					withUserId = parseInt record.with_user_id
					user.deleteShared record.object, record.subscribe_object, withUserId

					clientIds = clientsIdsForUserId[withUserId]
					if clientIds
						for clientId in clientIds
							user.removeSubscriber clientId, record.object

				changes.shared_objects['G' + record.id] = 'deleted'

			user.sendUpdate changes, '*'

		sendResponse 'ok'

	alterPermission: (params, sendResponse) ->
		User.operate params.userId, (user) ->
			switch params.action
				when 'create'
					user.addPermission params.permission.object, params.permission.userId, params.permission.level
				when 'delete'
					user.deletePermission params.permission.object, params.permission.userId
				when 'update'
					user.updatePermission params.permission.object, params.permission.userId, params.permission.level
			user.done()
		sendResponse 'ok'

	collaborators: (user, params, sendResponse) ->
		validate params.changes, 'json', 
			->
				user.sendUpdate params.changes, '*'
				if params.object
					user.sendUpdate params.changes, params.object
				sendResponse 'ok'
			-> sendResponse 'invalidInput'

	sendUpdate: (params, sendResponse) ->
		validate params.changes, 'json', 
			->
				User.operate params.userId, (user) ->
					user.sendUpdate params.changes, '*'
					user.done()
			->
		sendResponse 'ok'

	update: (user, params, sendResponse) ->
		validate params.changes, 'json',
			(changes) ->
				user.hasPermissions params.clientId, 'update', changes, (permission) ->
					if permission
						user.update params.clientId, params.updateToken, params.changes, (response) ->
							sendResponse response
					else
						sendResponse 'not allowed'
			-> sendResponse 'invalidInput'


	subscribe: (user, params, sendResponse) ->
		if params.serverId
			clientIdsByRouterId[params.serverId] ?= {}
			clientIdsByRouterId[params.serverId][params.clientId] = true
			routerIdForClientId[params.clientId] = params.serverId


		user.hasPermissions params.clientId, 'subscribe', params.object, params.key, (permission) ->
			if permission
				userIdForClientId params.clientId, (userId) ->
					clientsIdsForUserId[userId] ?= []
					if !(params.clientId in clientsIdsForUserId[userId])
						clientsIdsForUserId[userId].push params.clientId

					if usersByClientId[params.clientId].subscribes
						user.addSubscriber params.clientId, params.object

					user.data params.object, ((data) ->
						sendResponse data), clientId:params.clientId
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

		if clientIdsByRouterId[params.serverId]?[clientId]
			delete clientIdsByRouterId[params.serverId][clientId]

		if routerIdForClientId[params.clientId]
			delete routerIdForClientId[params.clientId]

		sendResponse ''

	retrieve: (params, sendResponse) ->
		request {
			url: "http://#{env.getUpdateServer()}/retrieve.php?clientId=#{params.clientId}",
			method: 'post'
			form:
				toRetrieve:params.records
		}, (err, response, body) ->
			sendResponse body

shuttingDown = false
executeCommand = (type, params, sendResponse) ->
	if commands[type]
		paramsStr = JSON.stringify(params)
		if paramsStr.length > 300
			paramsStr = paramsStr.substr(0, 300) + '...'.blue
		console.log 'command'.blue, type, paramsStr
		commandError = commandResponse = logId = null
		d = domain.create()
		
		if env.log
			timestamp = new Date().getTime()
			processLogsCol.insert {timestamp:timestamp, type:type, params:params}, (err, records) ->
				if !err
					logId = records[0]._id
					if commandResponse
						processLogsCol.update {_id:logId}, $set:response:commandResponse, ->
					else if commandError
						processLogsCol.update {_id:logId}, $set:error:message:commandError.message, stack:commandError.stack, -> process.exit()
				else
					console.log 'error inserting log'
					if commandError
						process.exit()

			d.on 'error', (err) ->
				console.log 'error', err.stack
				if logId
					processLogsCol.update {_id:logId}, $set:error:message:err.message, stack:err.stack, -> process.exit()
				else
					commandError = err

				try
					app.close()
				catch e

		else
			d.on 'error', (err) ->
				timestamp = new Date().getTime()
				console.log 'error', err.stack
				mongoDb.collection('errors').insert process:serverProcessId, request:{timestamp:timestamp, type:type, params:params}, error:{error:message:err.message, stack:err.stack}, ->
					process.exit()

				try
					app.close()
				catch e

		d.run ->
			# throw new Error()
			func = if _.isFunction commands[type] then commands[type] else commands[type].command

			# operate = commands[type].operate !== false && params.userId? && func.length === 3

			if params.userId? && commands[type].length == 3
				User.operate params.userId, (user) ->
					if user
						commands[type] user, params, (response) ->
							if logId
								processLogsCol.update {_id:logId}, $set:response:response, ->
							else if env.log
								commandResponse = response
							sendResponse response
							user.done()
					else
						sendResponse 'invalidUserId'
			else
				commands[type] params, sendResponse
	else
		sendResponse 'invalidCommand'


start = ->
	console.log 'started'
	for commandName, __ of commands
		do (commandName) ->
			app.post "/#{commandName}", (req, res) ->				
				process.nextTick -> executeCommand commandName, req.body, (response) ->
					res.header 'Access-Control-Allow-Origin', env.webappOrigin
					res.header 'Access-Control-Allow-Credentials', 'true'
					res.send response

	app.post '/port/started', (req, res) ->
		if clientIdsByRouterId[req.body.serverId]
			clientIds = clientIdsByRouterId[req.body.serverId]
			for clientId,__ of clientIds
				subscriptions = _.cloneDeep User.clientSubscriptions[clientId]
				for userId, objects of subscriptions
					user = User.user userId
					for object in objects
						user.removeSubscriber clientId, object
			delete clientIdsByRouterId[req.body.serverId]
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
	doInit = ->
		MongoClient.connect env.mongoDb, (err, db) ->
			mongoDb = db
			processLogsCol = mongoDb.collection "processLogs_#{serverProcessId}"

			count = 0
			length = _.size portServers
			for id,portServer of portServers
				request {
					url: "http://#{portServer}/gateway/started",
					method:'post'
					form:
						serverId:serverId
				}, (error) ->
					console.log 'has error', error if error
					if ++count == length
						start()

	doInit()

	# request {
	# 	method:'get'
	# 	url: "http://#{env.getUpdateServer()}/saveSnapshot.php?id=#{serverProcessId}"
	# }, (error, response, body) =>
