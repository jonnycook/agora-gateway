// Generated by CoffeeScript 1.7.1
var MongoClient, User, app, bodyParser, clientIdsByServerId, clientsIdsForUserId, commands, connection, doInit, domain, env, executeCommand, express, mongoDb, mysql, parse, processLogsCol, request, resolveUserId, serverId, serverProcessId, shuttingDown, snapshot, start, userIdForClientId, userIdsByClientId, validate, _,
  __slice = [].slice,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

serverProcessId = new Date().getTime();

serverId = 1;

domain = require('domain');

env = null;

if (process.argv[2]) {
  env = require('./env.test');
} else {
  env = require('./env');
}

mysql = require('mysql');

_ = require('lodash');

express = require('express');

bodyParser = require('body-parser');

request = require('request');

require('colors');

require('source-map-support').install();

MongoClient = require('mongodb').MongoClient;

mongoDb = null;

processLogsCol = null;

clientIdsByServerId = {};

clientsIdsForUserId = {};

parse = require('./utils').parse;

connection = mysql.createConnection(env.db);

connection.connect();

app = express();

app.use(bodyParser({
  limit: '50mb'
}));

app.listen(env.httpPort);

userIdsByClientId = {};

userIdForClientId = function(clientId, cb) {
  if (userIdsByClientId[clientId]) {
    return cb(userIdsByClientId[clientId]);
  } else {
    return connection.query("SELECT user_id FROM clients WHERE client_id = '" + clientId + "'", function(error, rows, fields) {
      var data;
      if (rows.length) {
        userIdsByClientId[clientId] = parseInt(rows[0].user_id);
        data = {};
        data["clients." + clientId] = userIdsByClientId[clientId];
        mongoDb.collection('snapshots').update({
          _id: serverProcessId
        }, {
          '$set': data
        }, function() {});
        return cb(userIdsByClientId[clientId]);
      } else {
        return cb(null);
      }
    });
  }
};

User = require('./User')(env, userIdForClientId, connection);

app.get('/debug', function(req, res) {
  var user, userId;
  console.log('====DEBUG====');
  userId = req.query.userId;
  user = User.user(userId);
  console.log('=user.subscribers=');
  console.log(user.subscribers);
  console.log('=user.outline=');
  console.log(user.outline);
  console.log('=user.shared=');
  console.log(user.shared);
  console.log('=User.clientSubscriptions=');
  console.log(User.clientSubscriptions);
  console.log('=clientIdsByServerId=');
  console.log(clientIdsByServerId);
  return res.send('');
});

app.get('/sync', function(req, res) {
  var user, userId;
  userId = req.query.userId;
  user = User.user(userId);
  user.syncClients();
  return res.send('');
});

validate = function() {
  var args, fail, i, result, results, success, type, value, _i, _j, _ref;
  args = 3 <= arguments.length ? __slice.call(arguments, 0, _i = arguments.length - 2) : (_i = 0, []), success = arguments[_i++], fail = arguments[_i++];
  results = [];
  for (i = _j = 0, _ref = args.length / 2; 0 <= _ref ? _j < _ref : _j > _ref; i = 0 <= _ref ? ++_j : --_j) {
    value = args[i];
    type = args[i + 1];
    switch (type) {
      case 'json':
        result = parse(value);
        if (result instanceof Error) {
          fail();
          return;
        } else {
          results[i] = result;
        }
    }
  }
  return success.apply(null, results);
};

resolveUserId = function(user, params, cb) {
  if (params.clientId === 'Carl Sagan') {
    return cb(params.userId);
  } else {
    return userIdForClientId(params.clientId, function(userId) {
      if (userId === parseInt(params.userId)) {
        return cb(userId);
      } else {
        return cb(null);
      }
    });
  }
};

commands = {
  error: function() {
    throw new Error();
  },
  init: function(user, params, sendResponse) {
    var _name;
    if (clientIdsByServerId[_name = params.serverId] == null) {
      clientIdsByServerId[_name] = {};
    }
    clientIdsByServerId[params.serverId][params.clientId] = true;
    return user.hasPermissions(params.clientId, 'init', function(permission) {
      if (permission) {
        user.addSubscriber(params.clientId, '*');
        return user.data('*', function(data) {
          return sendResponse(data);
        });
      } else {
        return sendResponse('not allowed');
      }
    });
  },
  'share/create': function(user, params, sendResponse) {
    resolveUserId(user, params, function(userId) {
      if (userId) {
        return request({
          url: "http://" + (env.getUpdateServer()) + "/shared/create.php?userId=" + userId,
          method: 'post',
          form: params
        }, function(err, response, body) {
          return console.log(body);
        });
      }
    });
    return sendResponse();
  },
  'share/delete': function(user, params, sendResponse) {
    resolveUserId(user, params, function(userId) {
      if (userId) {
        return request({
          url: "http://" + (env.getUpdateServer()) + "/shared/delete.php?userId=" + userId,
          method: 'post',
          form: params
        });
      }
    });
    return sendResponse();
  },
  'share/update': function(user, params, sendResponse) {
    resolveUserId(user, params, function(userId) {
      if (userId) {
        return request({
          url: "http://" + (env.getUpdateServer()) + "/shared/update.php?userId=" + userId,
          method: 'post',
          form: params
        });
      }
    });
    return sendResponse();
  },
  shared: function(user, params, sendResponse) {
    var action, changes, clientId, clientIds, record, withUserId, _i, _len, _ref;
    record = params.record;
    action = params.action;
    if ((_ref = user.subscribers) != null ? _ref['*'] : void 0) {
      changes = {
        shared_objects: {}
      };
      if (action === 'create') {
        if (user.shared && parseInt(record.user_id) === user.id) {
          if (!user.shared[record.object]) {
            user.shared[record.object] = [];
          }
          user.shared[record.object].push(parseInt(record.with_user_id));
        }
        changes.shared_objects['G' + record.id] = {
          user_id: 'G' + record.user_id,
          title: record.title,
          with_user_id: 'G' + record.with_user_id,
          object: record.object,
          user_name: record.user_name,
          with_user_name: record.with_user_name
        };
      }
      if (action === 'update') {
        changes.shared_objects['G' + record.id] = {
          title: record.title
        };
      } else if (action === 'delete') {
        if (record.with_user_id) {
          withUserId = parseInt(record.with_user_id);
          if (user.shared) {
            if (user.shared[record.object]) {
              _.pull(user.shared[record.object], withUserId);
              if (!user.shared[record.object].length) {
                delete user.shared[record.object];
              }
            }
          }
          clientIds = clientsIdsForUserId[withUserId];
          if (clientIds) {
            for (_i = 0, _len = clientIds.length; _i < _len; _i++) {
              clientId = clientIds[_i];
              user.removeSubscriber(clientId, record.object);
            }
          }
        }
        changes.shared_objects['G' + record.id] = 'deleted';
      }
      user.sendUpdate(changes, '*');
    }
    return sendResponse('ok');
  },
  collaborators: function(user, params, sendResponse) {
    return validate(params.changes, 'json', function() {
      user.sendUpdate(params.changes, '*');
      if (params.object) {
        user.sendUpdate(params.changes, params.object);
      }
      return sendResponse('ok');
    }, function() {
      return sendResponse('invalidInput');
    });
  },
  update: function(user, params, sendResponse) {
    return validate(params.changes, 'json', function(changes) {
      return user.hasPermissions(params.clientId, 'update', changes, function(permission) {
        if (permission) {
          return user.update(params.clientId, params.updateToken, params.changes, function(response) {
            return sendResponse(response);
          });
        } else {
          return sendResponse('not allowed');
        }
      });
    }, function() {
      return sendResponse('invalidInput');
    });
  },
  subscribe: function(user, params, sendResponse) {
    var _name;
    if (clientIdsByServerId[_name = params.serverId] == null) {
      clientIdsByServerId[_name] = {};
    }
    clientIdsByServerId[params.serverId][params.clientId] = true;
    return user.hasPermissions(params.clientId, 'subscribe', params.object, params.key, function(permission) {
      if (permission) {
        return userIdForClientId(params.clientId, function(userId) {
          var _ref;
          if (clientsIdsForUserId[userId] == null) {
            clientsIdsForUserId[userId] = [];
          }
          if (!(_ref = params.clientId, __indexOf.call(clientsIdsForUserId[userId], _ref) >= 0)) {
            clientsIdsForUserId[userId].push(params.clientId);
          }
          user.addSubscriber(params.clientId, params.object);
          return user.data(params.object, function(data) {
            return sendResponse(data);
          });
        });
      } else {
        return sendResponse('not allowed');
      }
    });
  },
  unsubscribe: function(user, params, sendResponse) {
    var clientId;
    clientId = params.clientId;
    user.removeSubscriber(clientId, params.object);
    return sendResponse('');
  },
  unsubscribeClient: function(params, sendResponse) {
    var clientId, object, objects, subscriptions, user, userId, _i, _len;
    clientId = params.clientId;
    if (User.clientSubscriptions[clientId]) {
      subscriptions = _.cloneDeep(User.clientSubscriptions[clientId]);
      for (userId in subscriptions) {
        objects = subscriptions[userId];
        user = User.user(userId);
        for (_i = 0, _len = objects.length; _i < _len; _i++) {
          object = objects[_i];
          user.removeSubscriber(clientId, object);
        }
      }
    }
    return sendResponse('');
  },
  retrieve: function(params, sendResponse) {
    return request({
      url: "http://" + (env.getUpdateServer()) + "/retrieve.php?clientId=" + params.clientId,
      method: 'post',
      form: {
        toRetrieve: params.records
      }
    }, function(err, response, body) {
      return sendResponse(body);
    });
  }
};

shuttingDown = false;

executeCommand = function(type, params, sendResponse) {
  var commandError, commandResponse, d, logId, timestamp;
  if (commands[type]) {
    console.log('command', type, params);
    commandError = commandResponse = logId = null;
    d = domain.create();
    if (env.log) {
      timestamp = new Date().getTime();
      processLogsCol.insert({
        timestamp: timestamp,
        type: type,
        params: params
      }, function(err, records) {
        if (!err) {
          logId = records[0]._id;
          if (commandResponse) {
            return processLogsCol.update({
              _id: logId
            }, {
              $set: {
                response: commandResponse
              }
            }, function() {});
          } else if (commandError) {
            return processLogsCol.update({
              _id: logId
            }, {
              $set: {
                error: {
                  message: commandError.message,
                  stack: commandError.stack
                }
              }
            }, function() {
              return process.exit();
            });
          }
        } else {
          console.log('error inserting log');
          if (commandError) {
            return process.exit();
          }
        }
      });
      d.on('error', function(err) {
        var e;
        console.log('error', err.stack);
        if (logId) {
          processLogsCol.update({
            _id: logId
          }, {
            $set: {
              error: {
                message: err.message,
                stack: err.stack
              }
            }
          }, function() {
            return process.exit();
          });
        } else {
          commandError = err;
        }
        try {
          return app.close();
        } catch (_error) {
          e = _error;
        }
      });
    } else {
      d.on('error', function(err) {
        var e;
        timestamp = new Date().getTime();
        console.log('error', err.stack);
        mongoDb.collection('errors').insert({
          process: serverProcessId,
          request: {
            timestamp: timestamp,
            type: type,
            params: params
          },
          error: {
            error: {
              message: err.message,
              stack: err.stack
            }
          }
        }, function() {
          return process.exit();
        });
        try {
          return app.close();
        } catch (_error) {
          e = _error;
        }
      });
    }
    return d.run(function() {
      if ((params.userId != null) && commands[type].length === 3) {
        return User.operate(params.userId, function(user) {
          if (user) {
            return commands[type](user, params, function(response) {
              if (logId) {
                processLogsCol.update({
                  _id: logId
                }, {
                  $set: {
                    response: response
                  }
                }, function() {});
              } else if (env.log) {
                commandResponse = response;
              }
              sendResponse(response);
              return user.done();
            });
          } else {
            return sendResponse('invalidUserId');
          }
        });
      } else {
        return commands[type](params, sendResponse);
      }
    });
  } else {
    return sendResponse('invalidCommand');
  }
};

start = function() {
  var commandName, __, _fn;
  console.log('started');
  _fn = function(commandName) {
    return app.post("/" + commandName, function(req, res) {
      return process.nextTick(function() {
        return executeCommand(commandName, req.body, function(response) {
          return res.send(response);
        });
      });
    });
  };
  for (commandName in commands) {
    __ = commands[commandName];
    _fn(commandName);
  }
  return app.post('/port/started', function(req, res) {
    var clientId, clientIds, object, objects, subscriptions, user, userId, _i, _len;
    if (clientIdsByServerId[req.body.serverId]) {
      clientIds = clientIdsByServerId[req.body.serverId];
      for (clientId in clientIds) {
        __ = clientIds[clientId];
        subscriptions = _.cloneDeep(User.clientSubscriptions[clientId]);
        for (userId in subscriptions) {
          objects = subscriptions[userId];
          user = User.user(userId);
          for (_i = 0, _len = objects.length; _i < _len; _i++) {
            object = objects[_i];
            user.removeSubscriber(clientId, object);
          }
        }
      }
      delete clientIdsByServerId[req.body.serverId];
    }
    return res.send('ok');
  });
};

if (process.argv[2]) {
  if (process.argv[2] === 'tests') {

  } else {
    snapshot = process.argv[2];
    start();
    request({
      url: "http://" + (env.getUpdateServer()) + "/restoreSnapshot.php?id=" + snapshot,
      method: 'get'
    }, function() {
      return MongoClient.connect(env.mongoDb, function(err, db) {
        var cursor;
        mongoDb = db;
        processLogsCol = mongoDb.collection("processLogs_" + snapshot);
        cursor = processLogsCol.find();
        return cursor.toArray(function(err, docs) {
          var current, next;
          current = 0;
          next = function() {
            var doc, params, type;
            if (current < docs.length) {
              doc = docs[current++];
              params = JSON.parse(doc.params);
              type = doc.type;
              console.log('>', type, params);
              if (params.userId && commands[type].length === 3) {
                return User.operate(params.userId, function(user) {
                  return commands[type](user, params, function(response) {
                    console.log('< %s'.blue, response);
                    user.done();
                    return next();
                  });
                });
              } else {
                return commands[type](params, function(response) {
                  console.log('< %s'.blue, response);
                  return next();
                });
              }
            } else {
              return console.log('done');
            }
          };
          return next();
        });
      });
    });
  }
} else {
  doInit = function() {
    return env.init(function() {
      return MongoClient.connect(env.mongoDb, function(err, db) {
        var count, portServer, _i, _len, _ref, _results;
        mongoDb = db;
        processLogsCol = mongoDb.collection("processLogs_" + serverProcessId);
        count = 0;
        _ref = env.portServers;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          portServer = _ref[_i];
          _results.push(request({
            url: "http://" + portServer + "/gateway/started",
            method: 'post',
            form: {
              serverId: serverId
            }
          }, function(error) {
            if (error) {
              console.log('has error', error);
            }
            if (++count === env.portServers.length) {
              return start();
            }
          }));
        }
        return _results;
      });
    });
  };
  doInit();
}
