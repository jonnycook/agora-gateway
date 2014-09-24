_ = require 'lodash'
request = require 'request'
util = require 'util'

graph = require './graph'
{parse:parse} = require './utils'
testLog = (args...) ->
	console.log 'TEST:'.green, args...


module.exports = 
	(env, userIdForClientId, connection) ->
		groupClientIdsByPort = (clientIds) ->
			grouped = {}
			for clientId in clientIds
				port = env.portForClient clientId
				grouped[port] ?= []
				grouped[port].push clientId
			grouped

		Graph =
			rels:{}
			root:{}
			inGraph:{}
			fields:
				root_elements: element_type:'value'
				bundle_elements: element_type:'value'
				list_elements: element_type:'value'
				feedback_items: creator_id:'int'
				feedback_item_replies: creator_id:'int'
				decision_suggestions: creator_id:'int'
				feedback_comments: creator_id:'int'
				feedback_comment_replies: creator_id:'int'

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
												if rows
													cb new Record table, row for row in rows
													tick()
												else
													console.log table, err
													throw new Error()
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

		class Response
			constructor: (@user, @clientId) ->
				@changesForSubscribers = {}

			addChangesForSubscribers: (object, table, id, changes) =>
				if @user.subscribers[object]
					@changesForSubscribers[object] ?= {}
					@changesForSubscribers[object][table] ?= {}
					if !@changesForSubscribers[object][table][id]
						@changesForSubscribers[object][table][id] = changes
					else
						_.extend @changesForSubscribers[object][table][id], changes

			setChangesForSubscribers: (object, changes) ->
				if @user.subscribers[object]
					@changesForSubscribers[object] = changes

			mergeChangesForSubscribers: (object, changes) ->
				if @user.subscribers[object]
					_.merge @changesForSubscribers[object], changes

			broadcast: ->
				if env.test
					testLog 'broadcast', util.inspect @changesForSubscribers, true, 10
				else
					for object,changes of @changesForSubscribers
						subscribers = _.without @user.subscribers[object], @clientId
						if subscribers.length
							grouped = groupClientIdsByPort subscribers
							changes = JSON.stringify changes
							for port, clientIds of grouped
								request
									url: "http://#{port}/update",
									method: 'post',
									form:
										clientIds:clientIds
										userId:@user.id
										# object:object
										changes:changes

		class UpdateOperation
			constructor: (@user, @response) ->
				@subscribers = user.subscribers
				@id = user.id
				@outline = user.outline

			addChanges: (table, id, changes) =>
				# testLog 'add', table, id, changes
				if table != 'activity' && !@outline[table]?[id]
					console.log 'missing %s.%s', table, id
					#TODO: Probably should handle this better...
					return

				r = if table == 'activity'
					Graph.owner @outline, table, changes
				else
					table:table, record:@outline[table][id]

				while r
					@response.addChangesForSubscribers "#{r.table}.#{r.record.id}", table, 'G' + id, changes
					r = Graph.owner @outline, r.table, r.record

			addBranch: (relTable, newId, cb) ->
				console.log 'addBranch', relTable, newId
				@user.data "#{relTable}.#{newId}", ((data) =>
					parse data,
						error: (error) =>
							# TODO: Figure out what to do here...
							console.log error
							cb 'error'
						success: (data) =>
							@response.mergeChangesForSubscribers '*', data
							@response.mergeChangesForSubscribers '/', data

							for dataTable, dataRecords of data
								for dataId, dataRecord of dataRecords
									dataId = parseInt(dataId.substr 1)
									@user.addToOutline dataTable, dataId, dataRecord
									@addChanges dataTable, dataId, dataRecord
							cb()
				), claim:true, collaborators:false		

			processChanges: (changes, cb) ->
				@response = new Response @user, @clientId

				# TODO: make more general
				delete changes.products
				delete changes.product_variants

				@response.setChangesForSubscribers '*', changes
				@response.setChangesForSubscribers '/', changes

				userId = "G#{@id}"
				if @subscribers['@'] && changes.users?[userId]
					# userChanges = users:{}
					# userChanges.users[userId] = changes.users[userId]
					# @response.setChangesForSubscribers '@', userChanges
					@response.addChangesForSubscribers '@', 'users', userId, changes.users[userId]

				done = =>
					@response.broadcast()
					cb()

				if @outline
					outlineChanges = {}
					for table, tableChanges of changes
						outlineChanges[table] = {}
						if Graph.inGraph table
							for id,recordChanges of tableChanges
								outlineChanges[table][parseInt(id.substr 1)] = recordChanges

					# extend outline
					for table, tableChanges of outlineChanges
						for id,recordChanges of tableChanges
							if recordChanges != 'deleted'
								@user.addToOutline table, id, recordChanges

					# add changes to response
					for table, tableChanges of outlineChanges
						for id,recordChanges of tableChanges
							@addChanges table, id, recordChanges

					count = 0
					toDelete = {}
					for table, tableChanges of outlineChanges
						# TODO: Make more general
						continue if table == 'activity'

						for id, recordChanges of tableChanges
							# prune outline
							if recordChanges == 'deleted'
								children = Graph.children @outline, table, @outline[table][id]
								for child in children
									toDelete[child.table] ?= {}
									toDelete[child.table][child.record.id] = true
								@user.deleteFromOutline table, id

							else
								for field of Graph.fields[table]
									# test if we are changing a branch
									if Graph.fields[table][field] == 'id' && (value = recordChanges[field]) && (rel = Graph.fieldRel?[table]?[field])
										relTable = if _.isFunction rel.table then rel.table @outline[table][id] else rel.table

										if Graph.inGraph relTable
											newId = parseInt value.substr 1
											if !@outline[relTable]?[newId]
												# console.log 'new branch', table, field, newId, relTable, value
												++count
												console.log table, field
												@addBranch relTable, newId, -> done() if !--count
											else
												# if toDelete[relTable]?[newId]
												delete toDelete[relTable]?[newId]

					# finish pruning outline
					for table, ids of toDelete
						for id, __ of ids
							for r in Graph.contained @outline, table, @outline[table][id]
								@user.deleteFromOutline r.table, r.record.id
							@user.deleteFromOutline table, id

					if !count
						done()
				else
					done()

			execute: (@clientId, updateToken, changes, cb) ->
				request {
					url: "http://#{env.getUpdateServer()}/update.php?clientId=#{clientId}&userId=#{@id}",
					method:'post'
					form:
						updateToken:updateToken
						changes:changes
				}, (error, response, body) =>
					if body in ['invalid update token', 'invalid client id']
						cb body
					else
						parse body,
							error: (error) =>
								console.log 'execute error', error
								cb 'error'
							success: (body) =>
								# testLog @outline
								if body.status == 'ok'
									if @subscribers && body.changes
										@processChanges body.changes, =>
											response = 
												status:'ok'
												updateToken:body.updateToken
												mapping:body.mapping

											if body.return
												changes = {}
												for table,ids of body.return
													changes[table] = {}
													for id in ids
														changes[table][id] = body.changes[table][id]
												response.changes = changes

											cb JSON.stringify response
									else
										response = 
											status:'ok'
											updateToken:body.updateToken
											mapping:body.mapping

										if body.changes && body.return
											changes = {}
											for table,ids of body.return
												changes[table] = {}
												for id in ids
													changes[table][id] = body.changes[table][id]
											response.changes = changes

										cb JSON.stringify response

								else if body.status == 'invalidUpdateToken'
									cb JSON.stringify
										status:'invalidUpdateToken'
										updateToken:body.updateToken
								else
									console.log 'invalid response', body
									cb 'error'

		class User
			@users:{}
			@clientSubscriptions: {}

			@user: (userId) ->
				@users[userId] ?= new User userId

			@userByClientId: (clientId, cb) ->
				userIdForClientId clientId, (userId) =>
					if userId
						cb @user userId
					else
						cb null

			@operateByClientId: (clientId, cb) ->
				@userByClientId clientId, (user) ->
					if user
						user.operate -> cb user
					else
						cb()

			@operate: (userId, cb) ->
				user = @user userId
				user.operate -> cb user

			addShared: (object, userId, role) ->
				if @shared
					@shared[object] ?= {}
					@shared[object][userId] = role:parseInt role

			deleteShared: (object, userId) ->
				if @shared
					if @shared[object]
						delete @shared[object][userId]
						if _.isEmpty @shared[object]
							delete @shared[object]

			addPermission: (object, userId, level) ->
				if !userId
					userId = null

				if @permissions
					@permissions[object] ?= {}
					@permissions[object][userId] = level:parseInt level

			updatePermission: (object, userId, level) ->
				if !userId
					userId = null
				console.log object, userId, level, @permissions?[object]?[userId]
				if @permissions?[object]?[userId]
					@permissions[object][userId].level = parseInt level

			deletePermission: (object, userId) ->
				if !userId
					userId = null
				if @permissions
					if @permissions[object]
						delete @permissions[object][userId]
						if _.isEmpty @permissions[object]
							delete @permissions[object]


			constructor: (id) ->
				@id = parseInt id
				@clientIds = {}

			operate: (cb) ->
				if @operating
					@queue ?= []
					@queue.push cb
				else
					@operating = true
					cb()

			done: ->
				@operating = false
				if @queue
					func = @queue.shift()
					if !@queue.length
						delete @queue
					@operating = true
					func()

			syncClients: ->
				if @subscribers
					for object, subscribers of @subscribers
						do (object, subscribers) =>
							@data object, (data) =>
								grouped = groupClientIdsByPort subscribers
								for port, clientIds of grouped
									request
										url: "http://#{port}/sync",
										method: 'post',
										form:
											clientIds:clientIds
											userId:@id
											object:object
											data:data

			sendUpdate: (changes, object) ->
				subscribers = @subscribers?[object]
				if subscribers
					grouped = groupClientIdsByPort subscribers
					if _.isObject changes
						changes = JSON.stringify changes
					for port, clientIds of grouped
						if !env.test
							request
								url: "http://#{port}/update",
								method: 'post',
								form:
									clientIds:clientIds
									userId:@id
									changes:changes


			stripForOutline: (table, inValues) ->
				values = {}
				for name,type of Graph.fields[table]
					if name of inValues
						if type == 'value'
							values[name] = inValues[name]
						else if type == 'int'
							values[name] = parseInt inValues[name]
						else if type == 'id'
							if inValues[name][0] == 'G'
								values[name] = parseInt inValues[name].substr 1
							else
								values[name] = parseInt inValues[name]
				values

			addToOutline: (table, id, inValues) ->
				# testLog @id, 'addToOutline', table, id, inValues
				# TODO: make more general
				return if table == 'activity'
				values = @stripForOutline table, inValues

				@outline[table] ?= {}
				if !@outline[table][id]
					values.id = parseInt id
					@outline[table][id] = values
				else
					for field,value of values
						if Graph.fields[table][field] == 'id' && value != @outline[table][id][field]
							contained = Graph.contained @outline, table, @outline[table][id]
							for r in contained
								@deleteFromOutline r.table, r.record.id
								# delete @outline[r.table][r.record.id]
							break
					_.extend @outline[table][id], values


			deleteFromOutline: (table, id) ->
				# testLog 'deleteFromOutline', table, id
				delete @outline[table][id]

			update: (clientId, updateToken, changes, cb) ->
				@initOutline =>
					updateOp = new UpdateOperation @
					updateOp.execute clientId, updateToken, changes, cb

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


			# userPermissions: ()

			permissionLevel: (object, userId) ->
				if @permissions?[object]?[userId]
					return @permissions?[object]?[userId].level

				if @shared?[object]?[userId]
					return switch @shared[object][userId].role
						when 0 then 3
						when 1 then 2

				if @permissions?[object]?[null]
					return @permissions[object][null].level

				return 0

			hasPermissions: (clientId, action, args..., cb) ->
				if clientId == 'Carl Sagan'
					cb true
				else
					userIdForClientId clientId, (userId) =>
						# TODO: should we handle this differently?
						if !userId
							console.log 'no user id'
							cb false
							return

						if action == 'init'
							if userId == @id
								cb true
							else
								cb false
						else if action == 'update'
							if userId == @id
								cb true
							else 
								@initPermissionData =>
									@initOutline (=>
										changes = args[0]
										if @shared['/']?[userId]
											for table,tableChanges of changes
												for id,recordChanges of tableChanges
													if id[0] == 'G' && !@outline?[table]?[id.substr 1]
														cb false
														return
										else
											for table,tableChanges of changes
												continue if table == 'activity'
												for id,recordChanges of tableChanges
													r = null
													mode = null

													if id[0] == 'G'
														r = table:table, record:@outline[table][id.substr 1]
														if recordChanges == 'deleted'
															mode = 'delete'
														else
															mode = 'update'
													else
														r = table:table, record:@stripForOutline table, recordChanges
														mode = 'create'

													if r?.record
														permitted = false
														while r
															object = "#{r.table}.#{r.record.id}"
															if (perm = @permissionLevel(object, userId)) >= 2#@shared[object]?[userId]
																if perm == 3
																	permitted = true
																else if perm == 2
																	if table in ['feedback_items', 'feedback_item_replies', 'decision_suggestions', 'feedback_comments', 'feedback_comment_replies']
																		if mode != 'create'
																			if @outline[table][id.substr 1].creator_id == userId
																				permitted = true
																		else
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
									cb true
									return
									connection.query "SELECT 1 FROM shared WHERE user_id = #{userId} && with_user_id = #{@id} || user_id = #{@id} && with_user_id = #{userId}", (err, rows) =>
										if rows.length
											cb true
										else if args[1]
											key = args[1]
											[uId, object] = key.split ' '
											connection.query "SELECT COUNT(*) c FROM shared WHERE user_id = #{uId} && object = '#{object}' && with_user_id IN (#{userId}, #{@id})", (err, rows) =>
												cb rows[0].c == 2
										else
											cb false
								else
									@initPermissionData =>
										if @permissionLevel(object, userId) >= 1
											cb true
										else
											cb false

			initPermissionData: (cb) ->
				@initShared => @initPermissions => cb()

			initShared: (cb) ->
				if !@shared
					@shared = {}
					connection.query "SELECT with_user_id, object, role FROM shared WHERE user_id = #{@id}", (error, rows, fields) =>
						for row in rows
							@addShared row.object, row.with_user_id, row.role
							# @shared[row.object] ?= {}
							# @shared[row.object][row.with_user_id] = role:row.role
						cb()
				else
					cb()

			initPermissions: (cb) ->
				if !@permissions
					@permissions = {}
					connection.query "SELECT user_id,object,level FROM permissions WHERE owner_id = #{@id}", (error, rows, fields) =>
						for row in rows
							@addPermission row.object, row.user_id, row.level
						cb()
				else
					cb()

			data: (object, cb, opts={}) ->
				opts.claim ?= false
				opts.collaborators ?= true
				request {
					url: "http://#{env.getUpdateServer()}/data.php?userId=#{@id}&object=#{object}&claim=#{if opts.claim then 1 else 0}&collaborators=#{if opts.collaborators then 1 else 0}#{if opts.clientId then "&clientId=#{opts.clientId}" else ''}",
				}, (err, response, body) ->
					cb body

			initOutline: (cb, force=false) ->
				if !@outline && (@needsOutline || force)
					@outline = {}
					delete @needsOutline
					connection.query "SELECT * FROM m_belts WHERE user_id = #{@id}", (err, rows, fields) =>
						if rows.length
							count = rows.length
							for row in rows
								record = new Record 'belts', row
								@addToOutline record.table, record.fields.id, record.fields
								record.contained (records) =>
									@addToOutline record.table, record.fields.id, record.fields for record in records
									-- count
									if !count
										cb()
						else
							cb()
				else
					cb()
