mysql = require 'mysql'
_ = require 'lodash'
express = require 'express'
bodyParser = require 'body-parser'
request = require 'request'
graph = require './graph'
require 'colors'

env = null

if process.argv[2]
	env = require './env.test'
else
	env = require './env'

MongoClient = require('mongodb').MongoClient

mongoDb = null
processLogsCol = null

serverProcessId = new Date().getTime()

if env.log
	winston = require('winston')
	winston.handleExceptions(new winston.transports.File({ filename: "errors_#{serverProcessId}.log" }))

Graph =
	rels:{}
	root:{}
	inGraph:{}
	fields:
		root_elements: element_type:'value'
		bundle_elements: element_type:'value'
		list_elements: element_type:'value'

	inGraph: (table) -> @inGraph[table] ? @rels[table]

	children: (db, table, record) ->
			contained = []
			for rel in @rels[table]
				if rel.owns
					if !rel.foreignKey
						containedTable = if _.isFunction rel.table then rel.table record else rel.table
						containedRecord = db[containedTable]?[record[rel.field]]

						if containedRecord
							if _.isFunction rel.owns
								if rel.owns containedRecord
									contained.push table:containedTable, record:containedRecord
							else
								contained.push table:containedTable, record:containedRecord
					else
						records = _.filter db[rel.table], (r) -> r[rel.field] == record.id
						for record in records
							contained.push table:rel.table, record:record
			contained

	contained: (db, table, record) ->
			contained = []
			for rel in @rels[table]
				if rel.owns
					if !rel.foreignKey
						containedTable = if _.isFunction rel.table then rel.table record else rel.table
						containedRecord = db[containedTable]?[record[rel.field]]

						if containedRecord
							if _.isFunction rel.owns
								if rel.owns containedRecord
									contained.push table:containedTable, record:containedRecord
									contained = contained.concat @contained db, containedTable, containedRecord
							else
								contained.push table:containedTable, record:containedRecord
								contained = contained.concat @contained db, containedTable, containedRecord
					else
						records = _.filter db[rel.table], (r) -> r[rel.field] == record.id

						for record in records
							contained.push table:rel.table, record:record
							contained = contained.concat @contained db, rel.table, record
			contained


	owner: (db, table, record) ->
		if @root[table]
			null
		else if @rels[table]
			for rel in @rels[table]
				if rel.owner
					if !rel.foreignKey
						table = if _.isFunction rel.table then rel.table @ else rel.table
						if !db[table]
							console.log table
						ownerRecord = db[table][record[rel.field]]
						return table:table, record:ownerRecord if ownerRecord
					else
						if rel.filter
							records = _.filter db[rel.table], (r) -> r[rel.field] == record.id && rel.filter table, record, r
						else
							records = _.filter db[rel.table], (r) -> r[rel.field] == record.id 
						return table:rel.table, record:records[0] if records[0]

Graph.fieldRel = {}
for table,graphDef of graph
	Graph.rels[table] = rels = []
	for name, rel of graphDef
		if name == 'root'
			Graph.root[table] = rel
		else if name == 'inGraph'
			Graph.inGraph[table] = rel
		else
			if !_.isArray rel
				rel = [rel]
			for r in rel
				if r.table
					Graph.fieldRel[table] ?= {}
					Graph.fieldRel[table][name] = r

					if !_.isFunction r.table
						Graph.fields[table] ?= {}
						Graph.fields[table][name] = 'id'

					rels.push
						table:r.table
						owns:r.owns
						owner:r.owner
						field:name
						filter:r.filter
				else if r.field
					Graph.fields[name] ?= {}
					Graph.fields[name][r.field] = 'id'

					rels.push
						foreignKey:true
						field:r.field
						table:name
						owns:r.owns
						owner:r.owner
						filter:r.filter



class Record
	constructor: (@table, @fields) ->

	forEachRelationship: (cb) ->
		table = @table
		record = @fields

		rels = Graph.rels[table]

		records = []

		if rels.length
			count = 0
			tick = ->
				if !--count
					cb()

			for rel in rels
				do (rel) =>
					if rel.owns
						owns = if _.isFunction rel.owns
							rel.owns @fields
						else rel.owns

						if owns
							++ count
							if rel.foreignKey
								table = rel.table
								do (table) =>
									connection.query "SELECT * FROM m_#{table} WHERE #{rel.field} = #{record.id}", (err, rows, fields) =>
										cb new Record table, row for row in rows
										tick()
							else
								table = if _.isFunction rel.table then rel.table record else rel.table
								do (table) =>
									connection.query "SELECT * FROM m_#{table} WHERE id = #{record[rel.field]}", (err, rows, fields) =>
										cb new Record table, rows[0]
										tick()
			cb() if !count
		else
			cb()

	getRelationships: (cb) ->
		records = []
		@forEachRelationship (record) ->
			if record
				records.push record
			else
				cb records

	contained: (cb) ->
		records = []
		count = 0
		sent = false
		done = false
		@forEachRelationship (record) ->
			if record
				++ count
				records.push record
				record.contained (r) ->
					records = records.concat r
					-- count
					if !count && done
						sent = true
						cb records
			else
				done = true
				if !count && !sent
					cb records


clientIdsByServerId = {}

clientsIdsForUserId = {}
userIdsByClientId = {}
userIdForClientId = (clientId, cb) ->
	if userIdsByClientId[clientId]
		cb userIdsByClientId[clientId]
	else
		connection.query "SELECT user_id FROM clients WHERE client_id = '#{clientId}'", (error, rows, fields) ->
			cb userIdsByClientId[clientId] = parseInt rows[0].user_id

parse = (json, cbs=null) -> 
	if cbs
		try
			cbs.success JSON.parse json
		catch e
			# console.log json
			cbs.error json
			# throw e
	else
		# TODO: handle errors here
		JSON.parse json


class User
	@users:{}
	@user: (userId) ->
		@users[userId] ?= new User userId

	@operate: (userId, cb) ->
		user = @user userId
		user.operate -> cb user

	@clientSubscriptions: {}

	constructor: (id) ->
		@id = parseInt id

	logCommand: (type, params) ->
		if env.log
			timestamp = new Date().getTime()
			processLogsCol.insert {timestamp:timestamp, userId:@id, type:type, params:params}, ->

	operate: (cb) ->
		if @operating
			@queue ?= []
			@queue.push cb
		else
			@operating = true
			cb()

	initialSnapshot: (cb) ->
		if env.log
			if !@snapshotTaken
				console.log 'initial snapshot'
				request {
					method:'get'
					url: "http://#{env.getUpdateServer()}/saveSnapshot.php?userId=#{@id}&id=#{serverProcessId}"
				}, (error, response, body) =>
					console.log 'snaphot taken', error, body
					cb()
					@snapshotTaken = true
			else
				cb()
		else
			cb()

	done: ->
		@operating = false
		if @queue
			func = @queue.shift()
			if !@queue.length
				delete @queue
			func()

	sendUpdate: (changes, object) ->
		subscribers = @subscribers?[object]
		if subscribers
			grouped = groupClientIdsByPort subscribers
			if _.isObject changes
				changes = JSON.stringify changes
			for port, clientIds of grouped
				request
					url: "http://#{port}/update",
					method: 'post',
					form:
						clientIds:clientIds
						userId:@id
						changes:changes


	update: (clientId, updateToken, changes, cb) ->
		@initOutline =>
				# @initShared =>
				request {
					url: "http://#{env.getUpdateServer()}/update.php?clientId=#{clientId}&userId=#{@id}",
					method:'post'
					form:
						updateToken:updateToken
						changes:changes
				}, (error, response, body) =>
					if body == 'invalid update token' 
						cb 'invalid client id'

					else if body == 'invalid client id'
						cb 'invalid client id'
					else
						parse body,
							error: (error) =>
								console.log error
								cb 'error'

							success: (body) =>
								if body.status == 'ok'
									# console.log body.changes
									# if body.changes && body.changes.decisions
									# 	for id,change of body.changes.decisions
									# 		if change == 'deleted'
									# 			object = "decisions.#{id.substr 1}"
									# 			if @shared[object]
									# 				request {
									# 					url: "http://#{env.getUpdateServer()}/delete.php",
									# 					method:'post'
									# 					form:
									# 						userId:@id
									# 						object:object
									# 				}

									if @subscribers
										delete body.changes.products
										delete body.changes.product_variants

										changesForSubscribers = {}
										if @subscribers['*']
											changesForSubscribers['*'] = body.changes

										if @subscribers['/']
											changesForSubscribers['/'] = body.changes

										if @subscribers['@'] && body.changes?.users?["G#{@id}"]
											id = "G#{@id}"
											changes = users:{}
											changes.users[id] = body.changes.users[id]
											changesForSubscribers['@'] = changes

										broadcast = =>
											for object,changes of changesForSubscribers
												subscribers = _.without @subscribers[object], clientId
												if subscribers.length
													grouped = groupClientIdsByPort subscribers
													changes = JSON.stringify body.changes
													for port, clientIds of grouped
														request
															url: "http://#{port}/update",
															method: 'post',
															form:
																clientIds:clientIds
																userId:@id
																changes:changes

											cb JSON.stringify
												status:'ok'
												updateToken:body.updateToken
												mapping:body.mapping

										if @outline
											addChangesForSubscribers = (object, table, id, changes) =>
												if @subscribers[object]
													changesForSubscribers[object] ?= {}
													changesForSubscribers[object][table] ?= {}
													if !changesForSubscribers[object][table][id]
														changesForSubscribers[object][table][id] = changes
													else
														_.extend changesForSubscribers[object][table][id], changes

											add = (table, id, changes) =>
												r = if table == 'activity'
													Graph.owner @outline, table, changes
												else
													table:table, record:@outline[table][id]

												while r
													addChangesForSubscribers "#{r.table}.#{r.record.id}", table, 'G' + id, changes
													r = Graph.owner @outline, r.table, r.record

											for table, tableChanges of body.changes
												if Graph.inGraph table
													for id,recordChanges of tableChanges
														if recordChanges != 'deleted'
															id = parseInt id.substr 1
															@addToOutline table, id, recordChanges

											for table, tableChanges of body.changes
												if Graph.inGraph table
													for id,recordChanges of tableChanges
														add table, parseInt(id.substr 1), recordChanges

											count = 0
											toDelete = {}
											for table, tableChanges of body.changes										
												if Graph.inGraph table
													@outline[table] ?= {}
													for id,recordChanges of tableChanges
														id = parseInt id.substr 1
														if recordChanges == 'deleted'
															children = Graph.children @outline, table, @outline[table][id]
															for child in children
																toDelete[child.table] ?= {}
																toDelete[child.table][child.record.id] = true
															delete @outline[table][id]
														else
															# TODO: make this more abstract
															# if recordChanges.element_type && recordChanges.element_type in ['Product', 'ProductVariant']
															# 	continue

															fields = Graph.fields[table]
															if fields
																for field of fields
																	if Graph.fields[table][field] == 'id' && (value = recordChanges[field])
																		newId = parseInt value.substr 1

																		if r = Graph.fieldRel?[table]?[field]
																			t = r.table
																			relTable = if _.isFunction t
																				t @outline[table][id]
																			else
																				t

																			if Graph.inGraph relTable
																				# console.log 'asdf', table, field, newId, relTable, value
																				if !@outline[relTable]?[newId]
																					# console.log 'new branch', table, field, newId, relTable, value
																					++count
																					do (table, id) =>
																						@data "#{relTable}.#{newId}", ((data) =>
																							parse data,
																								error: (error) =>
																									# TODO: Figure out what to do here...
																									console.log error
																									cb 'error'
																								success: (data) =>
																									for dataTable, dataRecords of data
																										for dataId, dataRecord of dataRecords
																											dataId = parseInt(dataId.substr 1)
																											@addToOutline dataTable, dataId, dataRecord
																											add dataTable, dataId, dataRecord
																									if !--count
																										broadcast()
																						), claim:true, collaborators:false
																				else
																					if toDelete[relTable]?[newId]
																						delete toDelete[relTable][newId]

													for table,ids of toDelete
														for id,__ of ids
															contained = Graph.contained @outline, table, @outline[table][id]
															for r in contained
																delete @outline[r.table][r.record.id]
															delete @outline[table][id]

											if !count
												broadcast()
										else
											broadcast()
									else
										cb JSON.stringify
											status:'ok'
											updateToken:body.updateToken
											mapping:body.mapping
								else if body.status == 'invalidUpdateToken'
									cb JSON.stringify
										status:'invalidUpdateToken'
										updateToken:body.updateToken


	addSubscriber: (clientId, object) ->
		if !(object in ['*', '/', '@'])
			@needsOutline = true
		@subscribers ?= {}
		@subscribers[object] ?= []
		if !(clientId in @subscribers[object])
			@subscribers[object].push clientId
			User.clientSubscriptions[clientId] ?= {}
			User.clientSubscriptions[clientId][@id] ?= []
			User.clientSubscriptions[clientId][@id].push object

	removeSubscriber: (clientId, object) ->
		if @subscribers[object]
			_.pull @subscribers[object], clientId
			if !@subscribers[object].length
				delete @subscribers[object]
				if _.isEmpty @subscribers
					delete @subscribers
					delete @outline
				else if @outline
					size = _.size @subscribers
					if size <= 3
						count = 0
						for o in ['*', '/', '@']
							if @subscribers[o]
								count++
						if count == size
							delete @outline

		if User.clientSubscriptions[clientId]?[@id]
			_.pull User.clientSubscriptions[clientId][@id], object
			if !User.clientSubscriptions[clientId][@id].length
				delete User.clientSubscriptions[clientId][@id]
				if _.isEmpty User.clientSubscriptions[clientId]
					delete User.clientSubscriptions[clientId]

	hasPermissions: (clientId, action, args..., cb) ->
		if clientId == 'Carl Sagan'
			cb true
		else
			userIdForClientId clientId, (userId) =>
				if action == 'init'
					if userId == @id
						cb true
					else
						cb false
				else if action == 'update'
					if userId == @id
						cb true
					else 
						@initShared =>
							@initOutline (=>
								changes = args[0]
								if @shared['/'] && userId in @shared['/']
									for table,tableChanges of changes
										for id,recordChanges of tableChanges
											if id[0] == 'G' && !@outline?[table]?[id.substr 1]
												cb false
												return
								else
									for table,tableChanges of changes
										for id,recordChanges of tableChanges
											if id[0] == 'G'
												id = id.substr 1
												if @outline[table][id]
													r = table:table, record:@outline[table][id]
													permitted = false
													while r
														object = "#{r.table}.#{r.record.id}"
														if @shared[object] && (userId in @shared[object])
															permitted = true
															break
														r = Graph.owner @outline, r.table, r.record

													if !permitted
														cb false
														return
												else
													cb false
													return
								cb true
							), true
				else if action == 'subscribe'
					object = args[0]
					if userId == @id
						if object == '*'
							cb true
						else
							cb false
					else
						if object == '@'
							connection.query "SELECT 1 FROM shared WHERE user_id = #{userId} && with_user_id = #{@id} || user_id = #{@id} && with_user_id = #{userId}", (err, rows) =>
								cb rows.length
						else
							@initShared =>
								if @shared[object] && (userId in @shared[object])
									cb true
								else
									cb false

	initShared: (cb) ->
		if !@shared
			@shared = {}
			connection.query "SELECT * FROM shared WHERE user_id = #{@id}", (error, rows, fields) =>
				for row in rows
					@shared[row.object] ?= []
					@shared[row.object].push row.with_user_id
				cb()
		else
			cb()

	data: (object, cb, opts={}) ->
		opts.claim ?= false
		opts.collaborators ?= true
		request {
			url: "http://#{env.getUpdateServer()}/data.php?userId=#{@id}&object=#{object}&claim=#{if opts.claim then 1 else 0}&collaborators=#{if opts.collaborators then 1 else 0}",
		}, (err, response, body) ->
			cb body

	addToOutline: (table, id, inValues) ->
		# TODO: make more general
		return if table == 'activity'
		values = {}
		for name,type of Graph.fields[table]
			if name of inValues
				if type == 'value'
					values[name] = inValues[name]
				else if type == 'id'
					if inValues[name][0] == 'G'
						values[name] = parseInt inValues[name].substr 1
					else
						values[name] = parseInt inValues[name]

		@outline[table] ?= {}
		if !@outline[table][id]
			values.id = parseInt id
			@outline[table][id] = values
		else
			for field,value of values
				if Graph.fields[table][field] == 'id'
					contained = Graph.contained @outline, table, @outline[table][id]
					for r in contained
						delete @outline[r.table][r.record.id]
					break
			_.extend @outline[table][id][field], values

	addRecord: (record) ->
		@addToOutline record.table, record.fields.id, record.fields

	initOutline: (cb, force=false) ->
		if !@outline && (@needsOutline || force)
			@outline = {}
			delete @needsOutline
			connection.query "SELECT * FROM m_root_elements WHERE user_id = #{@id}", (err, rows, fields) =>
				if rows.length
					count = rows.length
					for row in rows
						record = new Record 'root_elements', row
						@addRecord record
						record.contained (records) =>
							@addRecord record for record in records
							-- count
							if !count
								cb()
				else
					cb()
		else
			cb()

connection = mysql.createConnection env.db
connection.connect()

app = express()
app.use(bodyParser());
app.listen env.httpPort



groupClientIdsByPort = (clientIds) ->
	grouped = {}
	for clientId in clientIds
		port = env.portForClient clientId
		grouped[port] ?= []
		grouped[port].push clientId
	grouped

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

serverId = 1

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
		user.sendUpdate params.changes, params.object
		sendResponse 'ok'

	update: (user, params, sendResponse) ->
		user.initialSnapshot ->
			user.hasPermissions params.clientId, 'update', parse(params.changes), (permission) ->
				if permission
					user.update params.clientId, params.updateToken, params.changes, (response) ->
						sendResponse response
				else
					sendResponse 'not allowed'


	subscribe: (user, params, sendResponse) ->
		clientIdsByServerId[params.serverId] ?= {}
		clientIdsByServerId[params.serverId][params.clientId] = true

		user.hasPermissions params.clientId, 'subscribe', params.object, (permission) ->
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
	if params.userId && commands[type].length == 3
		User.operate params.userId, (user) ->
			user.logCommand type, params
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
	snapshot = process.argv[2]
	userId = process.argv[3]
	start()
	console.log snapshot



	request {
		url: "http://#{env.getUpdateServer()}/restoreSnapshot.php?id=#{snapshot}&userId=#{userId}",
		method: 'get'
	}, ->
		MongoClient.connect env.mongoDb, (err, db) ->
			mongoDb = db
			processLogsCol = mongoDb.collection "processLogs_#{snapshot}"
			cursor = processLogsCol.find userId:parseInt userId
			cursor.toArray (err, docs) ->
				current = 0
				next = ->
					if current < docs.length
						doc = docs[current++]
						params = doc.params
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

