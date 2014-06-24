// Generated by CoffeeScript 1.7.1
var graph, parse, request, testLog, util, _,
  __slice = [].slice,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

_ = require('lodash');

request = require('request');

util = require('util');

graph = require('./graph');

parse = require('./utils').parse;

testLog = function() {
  var args;
  args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
  return console.log.apply(console, ['TEST:'.green].concat(__slice.call(args)));
};

module.exports = function(env, userIdForClientId, connection) {
  var Graph, Record, Response, UpdateOperation, User, graphDef, groupClientIdsByPort, name, r, rel, rels, table, _base, _base1, _base2, _i, _len;
  groupClientIdsByPort = function(clientIds) {
    var clientId, grouped, port, _i, _len;
    grouped = {};
    for (_i = 0, _len = clientIds.length; _i < _len; _i++) {
      clientId = clientIds[_i];
      port = env.portForClient(clientId);
      if (grouped[port] == null) {
        grouped[port] = [];
      }
      grouped[port].push(clientId);
    }
    return grouped;
  };
  Graph = {
    rels: {},
    root: {},
    inGraph: {},
    fields: {
      root_elements: {
        element_type: 'value'
      },
      bundle_elements: {
        element_type: 'value'
      },
      list_elements: {
        element_type: 'value'
      }
    },
    inGraph: function(table) {
      var _ref;
      return (_ref = this.inGraph[table]) != null ? _ref : this.rels[table];
    },
    children: function(db, table, record) {
      var contained, containedRecord, containedTable, records, rel, _i, _j, _len, _len1, _ref, _ref1;
      contained = [];
      _ref = this.rels[table];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        rel = _ref[_i];
        if (rel.owns) {
          if (!rel.foreignKey) {
            containedTable = _.isFunction(rel.table) ? rel.table(record) : rel.table;
            containedRecord = (_ref1 = db[containedTable]) != null ? _ref1[record[rel.field]] : void 0;
            if (containedRecord) {
              if (_.isFunction(rel.owns)) {
                if (rel.owns(containedRecord)) {
                  contained.push({
                    table: containedTable,
                    record: containedRecord
                  });
                }
              } else {
                contained.push({
                  table: containedTable,
                  record: containedRecord
                });
              }
            }
          } else {
            records = _.filter(db[rel.table], function(r) {
              return r[rel.field] === record.id;
            });
            for (_j = 0, _len1 = records.length; _j < _len1; _j++) {
              record = records[_j];
              contained.push({
                table: rel.table,
                record: record
              });
            }
          }
        }
      }
      return contained;
    },
    contained: function(db, table, record) {
      var contained, containedRecord, containedTable, records, rel, _i, _j, _len, _len1, _ref, _ref1;
      contained = [];
      _ref = this.rels[table];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        rel = _ref[_i];
        if (rel.owns) {
          if (!rel.foreignKey) {
            containedTable = _.isFunction(rel.table) ? rel.table(record) : rel.table;
            containedRecord = (_ref1 = db[containedTable]) != null ? _ref1[record[rel.field]] : void 0;
            if (containedRecord) {
              if (_.isFunction(rel.owns)) {
                if (rel.owns(containedRecord)) {
                  contained.push({
                    table: containedTable,
                    record: containedRecord
                  });
                  contained = contained.concat(this.contained(db, containedTable, containedRecord));
                }
              } else {
                contained.push({
                  table: containedTable,
                  record: containedRecord
                });
                contained = contained.concat(this.contained(db, containedTable, containedRecord));
              }
            }
          } else {
            records = _.filter(db[rel.table], function(r) {
              return r[rel.field] === record.id;
            });
            for (_j = 0, _len1 = records.length; _j < _len1; _j++) {
              record = records[_j];
              contained.push({
                table: rel.table,
                record: record
              });
              contained = contained.concat(this.contained(db, rel.table, record));
            }
          }
        }
      }
      return contained;
    },
    owner: function(db, table, record) {
      var ownerRecord, records, rel, _i, _len, _ref;
      if (this.root[table]) {
        return null;
      } else if (this.rels[table]) {
        _ref = this.rels[table];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          rel = _ref[_i];
          if (rel.owner) {
            if (!rel.foreignKey) {
              table = _.isFunction(rel.table) ? rel.table(this) : rel.table;
              if (!db[table]) {
                console.log(table);
              }
              ownerRecord = db[table][record[rel.field]];
              if (ownerRecord) {
                return {
                  table: table,
                  record: ownerRecord
                };
              }
            } else {
              if (rel.filter) {
                records = _.filter(db[rel.table], function(r) {
                  return r[rel.field] === record.id && rel.filter(table, record, r);
                });
              } else {
                records = _.filter(db[rel.table], function(r) {
                  return r[rel.field] === record.id;
                });
              }
              if (records[0]) {
                return {
                  table: rel.table,
                  record: records[0]
                };
              }
            }
          }
        }
      }
    }
  };
  Graph.fieldRel = {};
  for (table in graph) {
    graphDef = graph[table];
    Graph.rels[table] = rels = [];
    for (name in graphDef) {
      rel = graphDef[name];
      if (name === 'root') {
        Graph.root[table] = rel;
      } else if (name === 'inGraph') {
        Graph.inGraph[table] = rel;
      } else {
        if (!_.isArray(rel)) {
          rel = [rel];
        }
        for (_i = 0, _len = rel.length; _i < _len; _i++) {
          r = rel[_i];
          if (r.table) {
            if ((_base = Graph.fieldRel)[table] == null) {
              _base[table] = {};
            }
            Graph.fieldRel[table][name] = r;
            if (!_.isFunction(r.table)) {
              if ((_base1 = Graph.fields)[table] == null) {
                _base1[table] = {};
              }
              Graph.fields[table][name] = 'id';
            }
            rels.push({
              table: r.table,
              owns: r.owns,
              owner: r.owner,
              field: name,
              filter: r.filter
            });
          } else if (r.field) {
            if ((_base2 = Graph.fields)[name] == null) {
              _base2[name] = {};
            }
            Graph.fields[name][r.field] = 'id';
            rels.push({
              foreignKey: true,
              field: r.field,
              table: name,
              owns: r.owns,
              owner: r.owner,
              filter: r.filter
            });
          }
        }
      }
    }
  }
  Record = (function() {
    function Record(table, fields) {
      this.table = table;
      this.fields = fields;
    }

    Record.prototype.forEachRelationship = function(cb) {
      var count, record, records, tick, _fn, _j, _len1;
      table = this.table;
      record = this.fields;
      rels = Graph.rels[table];
      records = [];
      if (rels.length) {
        count = 0;
        tick = function() {
          if (!--count) {
            return cb();
          }
        };
        _fn = (function(_this) {
          return function(rel) {
            var owns;
            if (rel.owns) {
              owns = _.isFunction(rel.owns) ? rel.owns(_this.fields) : rel.owns;
              if (owns) {
                ++count;
                if (rel.foreignKey) {
                  table = rel.table;
                  return (function(table) {
                    return connection.query("SELECT * FROM m_" + table + " WHERE " + rel.field + " = " + record.id, function(err, rows, fields) {
                      var row, _k, _len2;
                      for (_k = 0, _len2 = rows.length; _k < _len2; _k++) {
                        row = rows[_k];
                        cb(new Record(table, row));
                      }
                      return tick();
                    });
                  })(table);
                } else {
                  table = _.isFunction(rel.table) ? rel.table(record) : rel.table;
                  return (function(table) {
                    return connection.query("SELECT * FROM m_" + table + " WHERE id = " + record[rel.field], function(err, rows, fields) {
                      cb(new Record(table, rows[0]));
                      return tick();
                    });
                  })(table);
                }
              }
            }
          };
        })(this);
        for (_j = 0, _len1 = rels.length; _j < _len1; _j++) {
          rel = rels[_j];
          _fn(rel);
        }
        if (!count) {
          return cb();
        }
      } else {
        return cb();
      }
    };

    Record.prototype.getRelationships = function(cb) {
      var records;
      records = [];
      return this.forEachRelationship(function(record) {
        if (record) {
          return records.push(record);
        } else {
          return cb(records);
        }
      });
    };

    Record.prototype.contained = function(cb) {
      var count, done, records, sent;
      records = [];
      count = 0;
      sent = false;
      done = false;
      return this.forEachRelationship(function(record) {
        if (record) {
          ++count;
          records.push(record);
          return record.contained(function(r) {
            records = records.concat(r);
            --count;
            if (!count && done) {
              sent = true;
              return cb(records);
            }
          });
        } else {
          done = true;
          if (!count && !sent) {
            return cb(records);
          }
        }
      });
    };

    return Record;

  })();
  Response = (function() {
    function Response(user, clientId) {
      this.user = user;
      this.clientId = clientId;
      this.addChangesForSubscribers = __bind(this.addChangesForSubscribers, this);
      this.changesForSubscribers = {};
    }

    Response.prototype.addChangesForSubscribers = function(object, table, id, changes) {
      var _base3, _base4;
      if (this.user.subscribers[object]) {
        if ((_base3 = this.changesForSubscribers)[object] == null) {
          _base3[object] = {};
        }
        if ((_base4 = this.changesForSubscribers[object])[table] == null) {
          _base4[table] = {};
        }
        if (!this.changesForSubscribers[object][table][id]) {
          return this.changesForSubscribers[object][table][id] = changes;
        } else {
          return _.extend(this.changesForSubscribers[object][table][id], changes);
        }
      }
    };

    Response.prototype.setChangesForSubscribers = function(object, changes) {
      if (this.user.subscribers[object]) {
        return this.changesForSubscribers[object] = changes;
      }
    };

    Response.prototype.mergeChangesForSubscribers = function(object, changes) {
      if (this.user.subscribers[object]) {
        return _.merge(this.changesForSubscribers[object], changes);
      }
    };

    Response.prototype.broadcast = function() {
      var changes, clientIds, grouped, object, port, subscribers, _ref, _results;
      if (env.test) {
        return testLog('broadcast', util.inspect(this.changesForSubscribers, true, 10));
      } else {
        _ref = this.changesForSubscribers;
        _results = [];
        for (object in _ref) {
          changes = _ref[object];
          subscribers = _.without(this.user.subscribers[object], this.clientId);
          if (subscribers.length) {
            grouped = groupClientIdsByPort(subscribers);
            changes = JSON.stringify(changes);
            _results.push((function() {
              var _results1;
              _results1 = [];
              for (port in grouped) {
                clientIds = grouped[port];
                _results1.push(request({
                  url: "http://" + port + "/update",
                  method: 'post',
                  form: {
                    clientIds: clientIds,
                    userId: this.user.id,
                    changes: changes
                  }
                }));
              }
              return _results1;
            }).call(this));
          } else {
            _results.push(void 0);
          }
        }
        return _results;
      }
    };

    return Response;

  })();
  UpdateOperation = (function() {
    function UpdateOperation(user, response) {
      this.user = user;
      this.response = response;
      this.addChanges = __bind(this.addChanges, this);
      this.subscribers = user.subscribers;
      this.id = user.id;
      this.outline = user.outline;
    }

    UpdateOperation.prototype.addChanges = function(table, id, changes) {
      var _ref, _results;
      if (table !== 'activity' && !((_ref = this.outline[table]) != null ? _ref[id] : void 0)) {
        console.log('missing %s.%s', table, id);
        return;
      }
      r = table === 'activity' ? Graph.owner(this.outline, table, changes) : {
        table: table,
        record: this.outline[table][id]
      };
      _results = [];
      while (r) {
        this.response.addChangesForSubscribers("" + r.table + "." + r.record.id, table, 'G' + id, changes);
        _results.push(r = Graph.owner(this.outline, r.table, r.record));
      }
      return _results;
    };

    UpdateOperation.prototype.addBranch = function(relTable, newId, cb) {
      return this.user.data("" + relTable + "." + newId, ((function(_this) {
        return function(data) {
          return parse(data, {
            error: function(error) {
              console.log(error);
              return cb('error');
            },
            success: function(data) {
              var dataId, dataRecord, dataRecords, dataTable;
              _this.response.mergeChangesForSubscribers('*', data);
              _this.response.mergeChangesForSubscribers('/', data);
              for (dataTable in data) {
                dataRecords = data[dataTable];
                for (dataId in dataRecords) {
                  dataRecord = dataRecords[dataId];
                  dataId = parseInt(dataId.substr(1));
                  _this.user.addToOutline(dataTable, dataId, dataRecord);
                  _this.addChanges(dataTable, dataId, dataRecord);
                }
              }
              return cb();
            }
          });
        };
      })(this)), {
        claim: true,
        collaborators: false
      });
    };

    UpdateOperation.prototype.processChanges = function(changes, cb) {
      var child, children, count, done, field, id, ids, newId, outlineChanges, recordChanges, relTable, tableChanges, toDelete, userId, value, __, _j, _k, _len1, _len2, _name, _ref, _ref1, _ref2, _ref3;
      this.response = new Response(this.user, this.clientId);
      delete changes.products;
      delete changes.product_variants;
      this.response.setChangesForSubscribers('*', changes);
      this.response.setChangesForSubscribers('/', changes);
      userId = "G" + this.id;
      if (this.subscribers['@'] && ((_ref = changes.users) != null ? _ref[userId] : void 0)) {
        this.response.addChangesForSubscribers('@', 'users', userId, changes.users[userId]);
      }
      done = (function(_this) {
        return function() {
          _this.response.broadcast();
          return cb();
        };
      })(this);
      if (this.outline) {
        outlineChanges = {};
        for (table in changes) {
          tableChanges = changes[table];
          outlineChanges[table] = {};
          if (Graph.inGraph(table)) {
            for (id in tableChanges) {
              recordChanges = tableChanges[id];
              outlineChanges[table][parseInt(id.substr(1))] = recordChanges;
            }
          }
        }
        for (table in outlineChanges) {
          tableChanges = outlineChanges[table];
          for (id in tableChanges) {
            recordChanges = tableChanges[id];
            if (recordChanges !== 'deleted') {
              this.user.addToOutline(table, id, recordChanges);
            }
          }
        }
        for (table in outlineChanges) {
          tableChanges = outlineChanges[table];
          for (id in tableChanges) {
            recordChanges = tableChanges[id];
            this.addChanges(table, id, recordChanges);
          }
        }
        count = 0;
        toDelete = {};
        for (table in outlineChanges) {
          tableChanges = outlineChanges[table];
          if (table === 'activity') {
            continue;
          }
          for (id in tableChanges) {
            recordChanges = tableChanges[id];
            if (recordChanges === 'deleted') {
              children = Graph.children(this.outline, table, this.outline[table][id]);
              for (_j = 0, _len1 = children.length; _j < _len1; _j++) {
                child = children[_j];
                if (toDelete[_name = child.table] == null) {
                  toDelete[_name] = {};
                }
                toDelete[child.table][child.record.id] = true;
              }
              this.user.deleteFromOutline(table, id);
            } else {
              for (field in Graph.fields[table]) {
                if (Graph.fields[table][field] === 'id' && (value = recordChanges[field])) {
                  relTable = _.isFunction(rel.table) ? rel.table(this.outline[table][id]) : rel.table;
                  if (Graph.inGraph(relTable)) {
                    newId = parseInt(value.substr(1));
                    if (!((_ref1 = this.outline[relTable]) != null ? _ref1[newId] : void 0)) {
                      ++count;
                      this.addBranch(relTable, newId, function() {
                        if (!--count) {
                          return done();
                        }
                      });
                    } else {
                      if ((_ref2 = toDelete[relTable]) != null) {
                        delete _ref2[newId];
                      }
                    }
                  }
                }
              }
            }
          }
        }
        for (table in toDelete) {
          ids = toDelete[table];
          for (id in ids) {
            __ = ids[id];
            _ref3 = Graph.contained(this.outline, table, this.outline[table][id]);
            for (_k = 0, _len2 = _ref3.length; _k < _len2; _k++) {
              r = _ref3[_k];
              this.user.deleteFromOutline(r.table, r.record.id);
            }
            this.user.deleteFromOutline(table, id);
          }
        }
        if (!count) {
          return done();
        }
      } else {
        return done();
      }
    };

    UpdateOperation.prototype.execute = function(clientId, updateToken, changes, cb) {
      this.clientId = clientId;
      return request({
        url: "http://" + (env.getUpdateServer()) + "/update.php?clientId=" + clientId + "&userId=" + this.id,
        method: 'post',
        form: {
          updateToken: updateToken,
          changes: changes
        }
      }, (function(_this) {
        return function(error, response, body) {
          if (body === 'invalid update token' || body === 'invalid client id') {
            return cb(body);
          } else {
            return parse(body, {
              error: function(error) {
                console.log('error', error);
                return cb('error');
              },
              success: function(body) {
                if (body.status === 'ok') {
                  if (_this.subscribers && body.changes) {
                    return _this.processChanges(body.changes, function() {
                      return cb(JSON.stringify({
                        status: 'ok',
                        updateToken: body.updateToken,
                        mapping: body.mapping
                      }));
                    });
                  } else {
                    return cb(JSON.stringify({
                      status: 'ok',
                      updateToken: body.updateToken,
                      mapping: body.mapping
                    }));
                  }
                } else if (body.status === 'invalidUpdateToken') {
                  return cb(JSON.stringify({
                    status: 'invalidUpdateToken',
                    updateToken: body.updateToken
                  }));
                } else {
                  console.log('invalid response', body);
                  return cb('error');
                }
              }
            });
          }
        };
      })(this));
    };

    return UpdateOperation;

  })();
  return User = (function() {
    User.users = {};

    User.clientSubscriptions = {};

    User.user = function(userId) {
      var _base3;
      return (_base3 = this.users)[userId] != null ? _base3[userId] : _base3[userId] = new User(userId);
    };

    User.userByClientId = function(clientId, cb) {
      return userIdForClientId(clientId, (function(_this) {
        return function(userId) {
          return cb(_this.user(userId));
        };
      })(this));
    };

    User.operateByClientId = function(clientId, cb) {
      return this.userByClientId(clientId, function(user) {
        return user.operate(function() {
          return cb(user);
        });
      });
    };

    User.operate = function(userId, cb) {
      var user;
      user = this.user(userId);
      return user.operate(function() {
        return cb(user);
      });
    };

    function User(id) {
      this.id = parseInt(id);
      this.clientIds = {};
    }

    User.prototype.operate = function(cb) {
      if (this.operating) {
        if (this.queue == null) {
          this.queue = [];
        }
        return this.queue.push(cb);
      } else {
        this.operating = true;
        return cb();
      }
    };

    User.prototype.done = function() {
      var func;
      this.operating = false;
      if (this.queue) {
        func = this.queue.shift();
        if (!this.queue.length) {
          delete this.queue;
        }
        return func();
      }
    };

    User.prototype.sendUpdate = function(changes, object) {
      var clientIds, grouped, port, subscribers, _ref, _results;
      subscribers = (_ref = this.subscribers) != null ? _ref[object] : void 0;
      if (subscribers) {
        grouped = groupClientIdsByPort(subscribers);
        if (_.isObject(changes)) {
          changes = JSON.stringify(changes);
        }
        _results = [];
        for (port in grouped) {
          clientIds = grouped[port];
          if (!env.test) {
            _results.push(request({
              url: "http://" + port + "/update",
              method: 'post',
              form: {
                clientIds: clientIds,
                userId: this.id,
                changes: changes
              }
            }));
          } else {
            _results.push(void 0);
          }
        }
        return _results;
      }
    };

    User.prototype.addToOutline = function(table, id, inValues) {
      var contained, field, type, value, values, _base3, _j, _len1, _ref;
      if (table === 'activity') {
        return;
      }
      values = {};
      _ref = Graph.fields[table];
      for (name in _ref) {
        type = _ref[name];
        if (name in inValues) {
          if (type === 'value') {
            values[name] = inValues[name];
          } else if (type === 'id') {
            if (inValues[name][0] === 'G') {
              values[name] = parseInt(inValues[name].substr(1));
            } else {
              values[name] = parseInt(inValues[name]);
            }
          }
        }
      }
      if ((_base3 = this.outline)[table] == null) {
        _base3[table] = {};
      }
      if (!this.outline[table][id]) {
        values.id = parseInt(id);
        return this.outline[table][id] = values;
      } else {
        for (field in values) {
          value = values[field];
          if (Graph.fields[table][field] === 'id' && value !== this.outline[table][id][field]) {
            contained = Graph.contained(this.outline, table, this.outline[table][id]);
            for (_j = 0, _len1 = contained.length; _j < _len1; _j++) {
              r = contained[_j];
              this.deleteFromOutline(r.table, r.record.id);
            }
            break;
          }
        }
        return _.extend(this.outline[table][id], values);
      }
    };

    User.prototype.deleteFromOutline = function(table, id) {
      return delete this.outline[table][id];
    };

    User.prototype.update = function(clientId, updateToken, changes, cb) {
      return this.initOutline((function(_this) {
        return function() {
          var updateOp;
          updateOp = new UpdateOperation(_this);
          return updateOp.execute(clientId, updateToken, changes, cb);
        };
      })(this));
    };

    User.prototype.addSubscriber = function(clientId, object) {
      var _base3, _base4, _base5, _name;
      if (!(object === '*' || object === '/' || object === '@')) {
        this.needsOutline = true;
      }
      if (this.subscribers == null) {
        this.subscribers = {};
      }
      if ((_base3 = this.subscribers)[object] == null) {
        _base3[object] = [];
      }
      if (!(__indexOf.call(this.subscribers[object], clientId) >= 0)) {
        this.subscribers[object].push(clientId);
        if ((_base4 = User.clientSubscriptions)[clientId] == null) {
          _base4[clientId] = {};
        }
        if ((_base5 = User.clientSubscriptions[clientId])[_name = this.id] == null) {
          _base5[_name] = [];
        }
        return User.clientSubscriptions[clientId][this.id].push(object);
      }
    };

    User.prototype.removeSubscriber = function(clientId, object) {
      var count, o, size, _j, _len1, _ref, _ref1;
      if (this.subscribers[object]) {
        _.pull(this.subscribers[object], clientId);
        if (!this.subscribers[object].length) {
          delete this.subscribers[object];
          if (_.isEmpty(this.subscribers)) {
            delete this.subscribers;
            delete this.outline;
          } else if (this.outline) {
            size = _.size(this.subscribers);
            if (size <= 3) {
              count = 0;
              _ref = ['*', '/', '@'];
              for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
                o = _ref[_j];
                if (this.subscribers[o]) {
                  count++;
                }
              }
              if (count === size) {
                delete this.outline;
              }
            }
          }
        }
      }
      if ((_ref1 = User.clientSubscriptions[clientId]) != null ? _ref1[this.id] : void 0) {
        _.pull(User.clientSubscriptions[clientId][this.id], object);
        if (!User.clientSubscriptions[clientId][this.id].length) {
          delete User.clientSubscriptions[clientId][this.id];
          if (_.isEmpty(User.clientSubscriptions[clientId])) {
            return delete User.clientSubscriptions[clientId];
          }
        }
      }
    };

    User.prototype.hasPermissions = function() {
      var action, args, cb, clientId, _j;
      clientId = arguments[0], action = arguments[1], args = 4 <= arguments.length ? __slice.call(arguments, 2, _j = arguments.length - 1) : (_j = 2, []), cb = arguments[_j++];
      if (clientId === 'Carl Sagan') {
        return cb(true);
      } else {
        return userIdForClientId(clientId, (function(_this) {
          return function(userId) {
            var object;
            if (action === 'init') {
              if (userId === _this.id) {
                return cb(true);
              } else {
                return cb(false);
              }
            } else if (action === 'update') {
              if (userId === _this.id) {
                return cb(true);
              } else {
                return _this.initShared(function() {
                  return _this.initOutline((function() {
                    var changes, id, object, permitted, recordChanges, tableChanges, _ref, _ref1;
                    changes = args[0];
                    if (_this.shared['/'] && __indexOf.call(_this.shared['/'], userId) >= 0) {
                      for (table in changes) {
                        tableChanges = changes[table];
                        for (id in tableChanges) {
                          recordChanges = tableChanges[id];
                          if (id[0] === 'G' && !((_ref = _this.outline) != null ? (_ref1 = _ref[table]) != null ? _ref1[id.substr(1)] : void 0 : void 0)) {
                            cb(false);
                            return;
                          }
                        }
                      }
                    } else {
                      for (table in changes) {
                        tableChanges = changes[table];
                        for (id in tableChanges) {
                          recordChanges = tableChanges[id];
                          if (id[0] === 'G') {
                            id = id.substr(1);
                            if (_this.outline[table][id]) {
                              r = {
                                table: table,
                                record: _this.outline[table][id]
                              };
                              permitted = false;
                              while (r) {
                                object = "" + r.table + "." + r.record.id;
                                if (_this.shared[object] && (__indexOf.call(_this.shared[object], userId) >= 0)) {
                                  permitted = true;
                                  break;
                                }
                                r = Graph.owner(_this.outline, r.table, r.record);
                              }
                              if (!permitted) {
                                cb(false);
                                return;
                              }
                            } else {
                              cb(false);
                              return;
                            }
                          }
                        }
                      }
                    }
                    return cb(true);
                  }), true);
                });
              }
            } else if (action === 'subscribe') {
              object = args[0];
              if (userId === _this.id) {
                if (object === '*') {
                  return cb(true);
                } else {
                  return cb(false);
                }
              } else {
                if (object === '@') {
                  return connection.query("SELECT 1 FROM shared WHERE user_id = " + userId + " && with_user_id = " + _this.id + " || user_id = " + _this.id + " && with_user_id = " + userId, function(err, rows) {
                    var key, uId, _ref;
                    if (rows.length) {
                      return cb(true);
                    } else if (args[1]) {
                      key = args[1];
                      _ref = key.split(' '), uId = _ref[0], object = _ref[1];
                      return connection.query("SELECT COUNT(*) c FROM shared WHERE user_id = " + uId + " && object = '" + object + "' && with_user_id IN (" + userId + ", " + _this.id + ")", function(err, rows) {
                        return cb(rows[0].c === 2);
                      });
                    } else {
                      return cb(false);
                    }
                  });
                } else {
                  return _this.initShared(function() {
                    if (_this.shared[object] && (__indexOf.call(_this.shared[object], userId) >= 0)) {
                      return cb(true);
                    } else {
                      return cb(false);
                    }
                  });
                }
              }
            }
          };
        })(this));
      }
    };

    User.prototype.initShared = function(cb) {
      if (!this.shared) {
        this.shared = {};
        return connection.query("SELECT * FROM shared WHERE user_id = " + this.id, (function(_this) {
          return function(error, rows, fields) {
            var row, _base3, _j, _len1, _name;
            for (_j = 0, _len1 = rows.length; _j < _len1; _j++) {
              row = rows[_j];
              if ((_base3 = _this.shared)[_name = row.object] == null) {
                _base3[_name] = [];
              }
              _this.shared[row.object].push(row.with_user_id);
            }
            return cb();
          };
        })(this));
      } else {
        return cb();
      }
    };

    User.prototype.data = function(object, cb, opts) {
      if (opts == null) {
        opts = {};
      }
      if (opts.claim == null) {
        opts.claim = false;
      }
      if (opts.collaborators == null) {
        opts.collaborators = true;
      }
      return request({
        url: "http://" + (env.getUpdateServer()) + "/data.php?userId=" + this.id + "&object=" + object + "&claim=" + (opts.claim ? 1 : 0) + "&collaborators=" + (opts.collaborators ? 1 : 0)
      }, function(err, response, body) {
        return cb(body);
      });
    };

    User.prototype.initOutline = function(cb, force) {
      if (force == null) {
        force = false;
      }
      if (!this.outline && (this.needsOutline || force)) {
        this.outline = {};
        delete this.needsOutline;
        return connection.query("SELECT * FROM m_belts WHERE user_id = " + this.id, (function(_this) {
          return function(err, rows, fields) {
            var count, record, row, _j, _len1, _results;
            if (rows.length) {
              count = rows.length;
              _results = [];
              for (_j = 0, _len1 = rows.length; _j < _len1; _j++) {
                row = rows[_j];
                record = new Record('belts', row);
                _this.addToOutline(record.table, record.fields.id, record.fields);
                _results.push(record.contained(function(records) {
                  var _k, _len2;
                  for (_k = 0, _len2 = records.length; _k < _len2; _k++) {
                    record = records[_k];
                    _this.addToOutline(record.table, record.fields.id, record.fields);
                  }
                  --count;
                  if (!count) {
                    return cb();
                  }
                }));
              }
              return _results;
            } else {
              return cb();
            }
          };
        })(this));
      } else {
        return cb();
      }
    };

    return User;

  })();
};

//# sourceMappingURL=User.map
