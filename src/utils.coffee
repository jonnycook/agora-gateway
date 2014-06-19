module.exports = 
	parse: (json, cbs=null) -> 
		if cbs
			obj = null
			try
				obj = JSON.parse json
			catch e
				# console.log json
				cbs.error json
				# throw e
			if obj
				cbs.success obj
		else
			# TODO: handle errors here
			JSON.parse json
