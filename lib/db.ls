require! \crypto
require! \base32
require! \arangojs
require! \aqb

olio.config.db      ?= {}
olio.config.db.host ?= \localhost
olio.config.db.port ?= \8529
olio.config.db.name ?= \test

db = null
collections = null

export connect = (name = olio.config.db.name) ->*
  arango = new arangojs "http://#{olio.config.db.host}:#{olio.config.db.port}"
  if not db := first((yield arango.databases!) |> filter -> it.name == name)
    db := yield arango.create-database name
  collections := (yield db.collections!)
  |> map -> [ it.name, it ]
  |> pairs-to-obj

export query = ->*
  yield (yield db.query ...&).all!

export create = (name, properties = {}) ->*
  if not collections[name]
    collections[name] = yield db.create-collection name
  first(yield query(aqb.insert(\@o).into(name).return-new(\o), o: { _key: (base32.encode crypto.random-bytes 6) } <<< properties))

aqb-simple-filter = (q, properties) ->
  for key, val of properties
    val = switch typeof! val
    | \Boolean  => aqb.bool val
    | \Number   => aqb.num val
    | \String   => aqb.str val
    | \List     => aqb.list val
    | \Object   => aqb.obj val
    | otherwise => throw 'Unrecognized type'
    q = q.filter(aqb.eq(aqb.ref("o.#key"), val))
  q

export find = (name, properties = {}) ->*
  if not collections[name]
    return []
  q = aqb.for(\o).in(name)
  q = aqb-simple-filter q, properties
  yield query(q.return(\o))

export destroy = (name, properties = {}) ->*
  if not collections[name]
    return []
  q = aqb.for(\o).in(name)
  q = aqb-simple-filter q, properties
  yield query(q.remove(\o).in(name))

export update = (doc) ->*
  first yield query """
    UPDATE @key WITH @doc IN #{doc._id.split '/' .0} OPTIONS { keepNull: false } LET updated = NEW RETURN updated
  """, key: doc._key, doc: doc

