#!/usr/bin/env coffee


_ = require 'underscore'
fs = require 'fs'
http = require 'http'
argv = (require 'optimist')
	.options 'o',
		alias: 'output'
		default: process.stdout
	.options 'd',
		alias: 'date'
		default: false
	.options 'a',
		alias: 'append'
		default: false
	.options 'u',
		alias: 'update'
		default: false
	.options 'n',
		alias: 'name'
		default: null
	.argv


SERVICE_URL = 'icanhazip.com'
CONTENT_TYPE = 'text/plain; charset=utf-8'
LOG_REGEX = /^(?:\[(?:.*?; )?(.*?)\] )?(\d+)\.(\d+)\.(\d+)\.(\d+)$/
IP_REGEX = /(\d+)\.(\d+)\.(\d+)\.(\d+)/
ENOENT_CODE = 'ENOENT'


if argv.u then argv.a = true
if argv.n is "@"
	argv.n = (do (os = require 'os').hostname).replace /\.local$/, ""

compareBuffers = (buffer1, buffer2) ->
	(buffer1.toString 'hex') is (buffer2.toString 'hex')

createAddressBuffer = (array) ->
	try
		bytes = for i in array
			if (isNaN i = Number i) or i < 0 or i > 255 then throw null
			i
		new Buffer bytes
	catch
		null


withOutput = (callback) ->
	if (filePath = argv.o) is process.stdout
		argv.u = argv.a = false
		callback filePath, null
	else
		address = null
		fn = (err, contents) ->
			if not err?
				if contents?
					name = argv.n
					for line in do (contents.split /\n/).reverse
						if (match = LOG_REGEX.exec line)? and match[1] is name
							if (address = createAddressBuffer match[2..5])?
								break

			else if err.code isnt ENOENT_CODE
				console.error "Unexpected error:", err.code
				process.exit err.errno

			stream = fs.createWriteStream filePath,
				encoding: 'utf8'
				flags: if argv.a then 'a' else 'w'
			callback stream, address
			do stream.end

		if argv.u then fs.readFile filePath, 'utf8', fn else fn null, null


request = http.request
	hostname: SERVICE_URL
,	(response) ->
	if response.statusCode is 200
		if do response.headers['content-type'].toLowerCase is CONTENT_TYPE
			response.on 'data', (data) ->
				responseBody = do data.toString

				if (match = IP_REGEX.exec responseBody)
					address = createAddressBuffer match[1..4]

					withOutput (stream, lastAddress) ->
						metaStrings = []
						if argv.d then metaStrings.push do (new Date).toISOString
						if argv.n then metaStrings.push argv.n
						
						if not argv.u or not lastAddress? or not compareBuffers address, lastAddress
							stream.write "#{if metaStrings.length then "[#{metaStrings.join '; '}] " else ""}#{(String i for i in address[0..3]).join '.'}\n"
						else console.info "IP address remains the same; output file not updated."
				else
					console.error "Invalid response body: expected IP address (received omitted)."
					process.exit 1
		else
			console.error "Invalid content type: expected `#{CONTENT_TYPE}`, received `#{response.headers['content-type']}`."
			process.exit 1
	else
		console.error "Invalid response: expected `200 OK`, received `#{response.statusCode}`"
		process.exit 1

request.on 'error', (error) ->
	console.error "Unexpected error:", err.code
	process.exit err.errno

do request.end