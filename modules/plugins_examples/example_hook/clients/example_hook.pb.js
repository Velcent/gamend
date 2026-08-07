/*eslint-disable block-scoped-var, id-length, no-control-regex, no-magic-numbers, no-mixed-operators, no-prototype-builtins, no-redeclare, no-shadow, no-var, sort-vars, default-case, jsdoc/require-param*/
import $protobuf from "protobufjs/minimal.js";

// Common aliases
const $Reader = $protobuf.Reader, $Writer = $protobuf.Writer, $util = $protobuf.util;
const $Object = $util.global.Object, $undefined = $util.global.undefined, $Error = $util.global.Error, $TypeError = $util.global.TypeError, $String = $util.global.String, $Number = $util.global.Number, $Array = $util.global.Array;

// Exported root namespace
const $root = $protobuf.roots["default"] || ($protobuf.roots["default"] = {});

export const example_hook = $root.example_hook = (() => {

    /**
     * Namespace example_hook.
     * @exports example_hook
     * @namespace
     */
    const example_hook = {};

    example_hook.v1 = (function() {

        /**
         * Namespace v1.
         * @memberof example_hook
         * @namespace
         */
        const v1 = {};

        v1.HelloProtoRequest = (function() {

            /**
             * Properties of a HelloProtoRequest.
             * @typedef {Object} example_hook.v1.HelloProtoRequest.$Properties
             * @property {string|null} [name] HelloProtoRequest name
             * @property {number|null} [repeat] HelloProtoRequest repeat
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */

            /**
             * Properties of a HelloProtoRequest.
             * @memberof example_hook.v1
             * @interface IHelloProtoRequest
             * @augments example_hook.v1.HelloProtoRequest.$Properties
             * @deprecated Use example_hook.v1.HelloProtoRequest.$Properties instead.
             */

            /**
             * Shape of a HelloProtoRequest.
             * @typedef {example_hook.v1.HelloProtoRequest.$Properties} example_hook.v1.HelloProtoRequest.$Shape
             */

            /**
             * Constructs a new HelloProtoRequest.
             * @memberof example_hook.v1
             * @classdesc Represents a HelloProtoRequest.
             * @constructor
             * @param {example_hook.v1.HelloProtoRequest.$Properties=} [properties] Properties to set
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */
            const HelloProtoRequest = function (properties) {
                if (properties)
                    for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                        if (properties[keys[i]] != null && keys[i] !== "__proto__")
                            this[keys[i]] = properties[keys[i]];
            };

            /**
             * HelloProtoRequest name.
             * @member {string} name
             * @memberof example_hook.v1.HelloProtoRequest
             * @instance
             */
            HelloProtoRequest.prototype.name = "";

            /**
             * HelloProtoRequest repeat.
             * @member {number} repeat
             * @memberof example_hook.v1.HelloProtoRequest
             * @instance
             */
            HelloProtoRequest.prototype.repeat = 0;

            /**
             * Encodes the specified HelloProtoRequest message. Does not implicitly {@link example_hook.v1.HelloProtoRequest.verify|verify} messages.
             * @function encode
             * @memberof example_hook.v1.HelloProtoRequest
             * @static
             * @param {example_hook.v1.HelloProtoRequest.$Properties} message HelloProtoRequest message or plain object to encode
             * @param {$protobuf.Writer} [writer] Writer to encode to
             * @returns {$protobuf.Writer} Writer
             */
            HelloProtoRequest.encode = function (message, writer, _depth) {
                if (!writer)
                    writer = $Writer.create();
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                if (message.name != null && $Object.hasOwnProperty.call(message, "name") && message.name !== "")
                    writer.uint32(/* id 1, wireType 2 =*/10).string(message.name);
                if (message.repeat != null && $Object.hasOwnProperty.call(message, "repeat") && message.repeat !== 0)
                    writer.uint32(/* id 2, wireType 0 =*/16).uint32(message.repeat);
                if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                    for (let i = 0; i < message.$unknowns.length; ++i)
                        writer.raw(message.$unknowns[i]);
                return writer;
            };

            /**
             * Decodes a HelloProtoRequest message from the specified reader or buffer.
             * @function decode
             * @memberof example_hook.v1.HelloProtoRequest
             * @static
             * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
             * @param {number} [length] Message length if known beforehand
             * @returns {example_hook.v1.HelloProtoRequest & example_hook.v1.HelloProtoRequest.$Shape} HelloProtoRequest
             * @throws {Error} If the payload is not a reader or valid buffer
             * @throws {$protobuf.util.ProtocolError} If required fields are missing
             */
            HelloProtoRequest.decode = function (reader, length, _end, _depth, _target) {
                if (!(reader instanceof $Reader))
                    reader = $Reader.create(reader);
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $Reader.recursionLimit)
                    throw $Error("max depth exceeded");
                let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.example_hook.v1.HelloProtoRequest(), value;
                while (reader.pos < end) {
                    let start = reader.pos;
                    let tag = reader.tag();
                    if (tag === _end) {
                        _end = $undefined;
                        break;
                    }
                    let wireType = tag & 7;
                    switch (tag >>>= 3) {
                    case 1: {
                            if (wireType !== 2)
                                break;
                            if ((value = reader.stringVerify()).length)
                                message.name = value;
                            else
                                delete message.name;
                            continue;
                        }
                    case 2: {
                            if (wireType !== 0)
                                break;
                            if (value = reader.uint32())
                                message.repeat = value;
                            else
                                delete message.repeat;
                            continue;
                        }
                    }
                    reader.skipType(wireType, _depth, tag);
                    if (!reader.discardUnknown) {
                        $util.makeProp(message, "$unknowns", false);
                        (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                    }
                }
                if (_end !== $undefined)
                    throw $Error("missing end group");
                return message;
            };

            /**
             * Creates a HelloProtoRequest message from a plain object. Also converts values to their respective internal types.
             * @function fromObject
             * @memberof example_hook.v1.HelloProtoRequest
             * @static
             * @param {Object.<string,*>} object Plain object
             * @returns {example_hook.v1.HelloProtoRequest} HelloProtoRequest
             */
            HelloProtoRequest.fromObject = function (object, _depth) {
                if (object instanceof $root.example_hook.v1.HelloProtoRequest)
                    return object;
                if (!$util.isObject(object))
                    throw $TypeError(".example_hook.v1.HelloProtoRequest: object expected");
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let message = new $root.example_hook.v1.HelloProtoRequest();
                if (object.name != null)
                    if (typeof object.name !== "string" || object.name.length)
                        message.name = $String(object.name);
                if (object.repeat != null)
                    if ($Number(object.repeat) !== 0)
                        message.repeat = object.repeat >>> 0;
                return message;
            };

            /**
             * Creates a plain object from a HelloProtoRequest message. Also converts values to other types if specified.
             * @function toObject
             * @memberof example_hook.v1.HelloProtoRequest
             * @static
             * @param {example_hook.v1.HelloProtoRequest} message HelloProtoRequest
             * @param {$protobuf.IConversionOptions} [options] Conversion options
             * @returns {Object.<string,*>} Plain object
             */
            HelloProtoRequest.toObject = function (message, options, _depth) {
                if (!options)
                    options = {};
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let object = {};
                if (options.defaults) {
                    object.name = "";
                    object.repeat = 0;
                }
                if (message.name != null && $Object.hasOwnProperty.call(message, "name"))
                    object.name = message.name;
                if (message.repeat != null && $Object.hasOwnProperty.call(message, "repeat"))
                    object.repeat = message.repeat;
                return object;
            };

            /**
             * Converts this HelloProtoRequest to JSON.
             * @function toJSON
             * @memberof example_hook.v1.HelloProtoRequest
             * @instance
             * @returns {Object.<string,*>} JSON object
             */
            HelloProtoRequest.prototype.toJSON = function() {
                return HelloProtoRequest.toObject(this, $protobuf.util.toJSONOptions);
            };

            /**
             * Gets the type url for HelloProtoRequest
             * @function getTypeUrl
             * @memberof example_hook.v1.HelloProtoRequest
             * @static
             * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
             * @returns {string} The type url
             */
            HelloProtoRequest.getTypeUrl = function(prefix) {
                if (prefix === $undefined)
                    prefix = "type.googleapis.com";
                return prefix + "/example_hook.v1.HelloProtoRequest";
            };

            return HelloProtoRequest;
        })();

        v1.HelloProtoReply = (function() {

            /**
             * Properties of a HelloProtoReply.
             * @typedef {Object} example_hook.v1.HelloProtoReply.$Properties
             * @property {string|null} [greeting] HelloProtoReply greeting
             * @property {number|null} [name_length] HelloProtoReply name_length
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */

            /**
             * Properties of a HelloProtoReply.
             * @memberof example_hook.v1
             * @interface IHelloProtoReply
             * @augments example_hook.v1.HelloProtoReply.$Properties
             * @deprecated Use example_hook.v1.HelloProtoReply.$Properties instead.
             */

            /**
             * Shape of a HelloProtoReply.
             * @typedef {example_hook.v1.HelloProtoReply.$Properties} example_hook.v1.HelloProtoReply.$Shape
             */

            /**
             * Constructs a new HelloProtoReply.
             * @memberof example_hook.v1
             * @classdesc Represents a HelloProtoReply.
             * @constructor
             * @param {example_hook.v1.HelloProtoReply.$Properties=} [properties] Properties to set
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */
            const HelloProtoReply = function (properties) {
                if (properties)
                    for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                        if (properties[keys[i]] != null && keys[i] !== "__proto__")
                            this[keys[i]] = properties[keys[i]];
            };

            /**
             * HelloProtoReply greeting.
             * @member {string} greeting
             * @memberof example_hook.v1.HelloProtoReply
             * @instance
             */
            HelloProtoReply.prototype.greeting = "";

            /**
             * HelloProtoReply name_length.
             * @member {number} name_length
             * @memberof example_hook.v1.HelloProtoReply
             * @instance
             */
            HelloProtoReply.prototype.name_length = 0;

            /**
             * Encodes the specified HelloProtoReply message. Does not implicitly {@link example_hook.v1.HelloProtoReply.verify|verify} messages.
             * @function encode
             * @memberof example_hook.v1.HelloProtoReply
             * @static
             * @param {example_hook.v1.HelloProtoReply.$Properties} message HelloProtoReply message or plain object to encode
             * @param {$protobuf.Writer} [writer] Writer to encode to
             * @returns {$protobuf.Writer} Writer
             */
            HelloProtoReply.encode = function (message, writer, _depth) {
                if (!writer)
                    writer = $Writer.create();
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                if (message.greeting != null && $Object.hasOwnProperty.call(message, "greeting") && message.greeting !== "")
                    writer.uint32(/* id 1, wireType 2 =*/10).string(message.greeting);
                if (message.name_length != null && $Object.hasOwnProperty.call(message, "name_length") && message.name_length !== 0)
                    writer.uint32(/* id 2, wireType 0 =*/16).uint32(message.name_length);
                if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                    for (let i = 0; i < message.$unknowns.length; ++i)
                        writer.raw(message.$unknowns[i]);
                return writer;
            };

            /**
             * Decodes a HelloProtoReply message from the specified reader or buffer.
             * @function decode
             * @memberof example_hook.v1.HelloProtoReply
             * @static
             * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
             * @param {number} [length] Message length if known beforehand
             * @returns {example_hook.v1.HelloProtoReply & example_hook.v1.HelloProtoReply.$Shape} HelloProtoReply
             * @throws {Error} If the payload is not a reader or valid buffer
             * @throws {$protobuf.util.ProtocolError} If required fields are missing
             */
            HelloProtoReply.decode = function (reader, length, _end, _depth, _target) {
                if (!(reader instanceof $Reader))
                    reader = $Reader.create(reader);
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $Reader.recursionLimit)
                    throw $Error("max depth exceeded");
                let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.example_hook.v1.HelloProtoReply(), value;
                while (reader.pos < end) {
                    let start = reader.pos;
                    let tag = reader.tag();
                    if (tag === _end) {
                        _end = $undefined;
                        break;
                    }
                    let wireType = tag & 7;
                    switch (tag >>>= 3) {
                    case 1: {
                            if (wireType !== 2)
                                break;
                            if ((value = reader.stringVerify()).length)
                                message.greeting = value;
                            else
                                delete message.greeting;
                            continue;
                        }
                    case 2: {
                            if (wireType !== 0)
                                break;
                            if (value = reader.uint32())
                                message.name_length = value;
                            else
                                delete message.name_length;
                            continue;
                        }
                    }
                    reader.skipType(wireType, _depth, tag);
                    if (!reader.discardUnknown) {
                        $util.makeProp(message, "$unknowns", false);
                        (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                    }
                }
                if (_end !== $undefined)
                    throw $Error("missing end group");
                return message;
            };

            /**
             * Creates a HelloProtoReply message from a plain object. Also converts values to their respective internal types.
             * @function fromObject
             * @memberof example_hook.v1.HelloProtoReply
             * @static
             * @param {Object.<string,*>} object Plain object
             * @returns {example_hook.v1.HelloProtoReply} HelloProtoReply
             */
            HelloProtoReply.fromObject = function (object, _depth) {
                if (object instanceof $root.example_hook.v1.HelloProtoReply)
                    return object;
                if (!$util.isObject(object))
                    throw $TypeError(".example_hook.v1.HelloProtoReply: object expected");
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let message = new $root.example_hook.v1.HelloProtoReply();
                if (object.greeting != null)
                    if (typeof object.greeting !== "string" || object.greeting.length)
                        message.greeting = $String(object.greeting);
                if (object.name_length != null)
                    if ($Number(object.name_length) !== 0)
                        message.name_length = object.name_length >>> 0;
                return message;
            };

            /**
             * Creates a plain object from a HelloProtoReply message. Also converts values to other types if specified.
             * @function toObject
             * @memberof example_hook.v1.HelloProtoReply
             * @static
             * @param {example_hook.v1.HelloProtoReply} message HelloProtoReply
             * @param {$protobuf.IConversionOptions} [options] Conversion options
             * @returns {Object.<string,*>} Plain object
             */
            HelloProtoReply.toObject = function (message, options, _depth) {
                if (!options)
                    options = {};
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let object = {};
                if (options.defaults) {
                    object.greeting = "";
                    object.name_length = 0;
                }
                if (message.greeting != null && $Object.hasOwnProperty.call(message, "greeting"))
                    object.greeting = message.greeting;
                if (message.name_length != null && $Object.hasOwnProperty.call(message, "name_length"))
                    object.name_length = message.name_length;
                return object;
            };

            /**
             * Converts this HelloProtoReply to JSON.
             * @function toJSON
             * @memberof example_hook.v1.HelloProtoReply
             * @instance
             * @returns {Object.<string,*>} JSON object
             */
            HelloProtoReply.prototype.toJSON = function() {
                return HelloProtoReply.toObject(this, $protobuf.util.toJSONOptions);
            };

            /**
             * Gets the type url for HelloProtoReply
             * @function getTypeUrl
             * @memberof example_hook.v1.HelloProtoReply
             * @static
             * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
             * @returns {string} The type url
             */
            HelloProtoReply.getTypeUrl = function(prefix) {
                if (prefix === $undefined)
                    prefix = "type.googleapis.com";
                return prefix + "/example_hook.v1.HelloProtoReply";
            };

            return HelloProtoReply;
        })();

        v1.ExampleLoadout = (function() {

            /**
             * Properties of an ExampleLoadout.
             * @typedef {Object} example_hook.v1.ExampleLoadout.$Properties
             * @property {number|null} [weapon_id] ExampleLoadout weapon_id
             * @property {Array.<number>|null} [perk_ids] ExampleLoadout perk_ids
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */

            /**
             * Properties of an ExampleLoadout.
             * @memberof example_hook.v1
             * @interface IExampleLoadout
             * @augments example_hook.v1.ExampleLoadout.$Properties
             * @deprecated Use example_hook.v1.ExampleLoadout.$Properties instead.
             */

            /**
             * Shape of an ExampleLoadout.
             * @typedef {example_hook.v1.ExampleLoadout.$Properties} example_hook.v1.ExampleLoadout.$Shape
             */

            /**
             * Constructs a new ExampleLoadout.
             * @memberof example_hook.v1
             * @classdesc Represents an ExampleLoadout.
             * @constructor
             * @param {example_hook.v1.ExampleLoadout.$Properties=} [properties] Properties to set
             * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
             */
            const ExampleLoadout = function (properties) {
                this.perk_ids = [];
                if (properties)
                    for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                        if (properties[keys[i]] != null && keys[i] !== "__proto__")
                            this[keys[i]] = properties[keys[i]];
            };

            /**
             * ExampleLoadout weapon_id.
             * @member {number} weapon_id
             * @memberof example_hook.v1.ExampleLoadout
             * @instance
             */
            ExampleLoadout.prototype.weapon_id = 0;

            /**
             * ExampleLoadout perk_ids.
             * @member {Array.<number>} perk_ids
             * @memberof example_hook.v1.ExampleLoadout
             * @instance
             */
            ExampleLoadout.prototype.perk_ids = $util.emptyArray;

            /**
             * Encodes the specified ExampleLoadout message. Does not implicitly {@link example_hook.v1.ExampleLoadout.verify|verify} messages.
             * @function encode
             * @memberof example_hook.v1.ExampleLoadout
             * @static
             * @param {example_hook.v1.ExampleLoadout.$Properties} message ExampleLoadout message or plain object to encode
             * @param {$protobuf.Writer} [writer] Writer to encode to
             * @returns {$protobuf.Writer} Writer
             */
            ExampleLoadout.encode = function (message, writer, _depth) {
                if (!writer)
                    writer = $Writer.create();
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                if (message.weapon_id != null && $Object.hasOwnProperty.call(message, "weapon_id") && message.weapon_id !== 0)
                    writer.uint32(/* id 1, wireType 0 =*/8).uint32(message.weapon_id);
                if (message.perk_ids != null && message.perk_ids.length)
                    writer.uint32(/* id 2, wireType 2 =*/18).uint32s(message.perk_ids);
                if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                    for (let i = 0; i < message.$unknowns.length; ++i)
                        writer.raw(message.$unknowns[i]);
                return writer;
            };

            /**
             * Decodes an ExampleLoadout message from the specified reader or buffer.
             * @function decode
             * @memberof example_hook.v1.ExampleLoadout
             * @static
             * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
             * @param {number} [length] Message length if known beforehand
             * @returns {example_hook.v1.ExampleLoadout & example_hook.v1.ExampleLoadout.$Shape} ExampleLoadout
             * @throws {Error} If the payload is not a reader or valid buffer
             * @throws {$protobuf.util.ProtocolError} If required fields are missing
             */
            ExampleLoadout.decode = function (reader, length, _end, _depth, _target) {
                if (!(reader instanceof $Reader))
                    reader = $Reader.create(reader);
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $Reader.recursionLimit)
                    throw $Error("max depth exceeded");
                let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.example_hook.v1.ExampleLoadout(), value;
                while (reader.pos < end) {
                    let start = reader.pos;
                    let tag = reader.tag();
                    if (tag === _end) {
                        _end = $undefined;
                        break;
                    }
                    let wireType = tag & 7;
                    switch (tag >>>= 3) {
                    case 1: {
                            if (wireType !== 0)
                                break;
                            if (value = reader.uint32())
                                message.weapon_id = value;
                            else
                                delete message.weapon_id;
                            continue;
                        }
                    case 2: {
                            if (wireType === 2) {
                                if (!(message.perk_ids && message.perk_ids.length))
                                    message.perk_ids = [];
                                reader.uint32s(message.perk_ids);
                                continue;
                            }
                            if (wireType !== 0)
                                break;
                            if (!(message.perk_ids && message.perk_ids.length))
                                message.perk_ids = [];
                            message.perk_ids.push(reader.uint32());
                            continue;
                        }
                    }
                    reader.skipType(wireType, _depth, tag);
                    if (!reader.discardUnknown) {
                        $util.makeProp(message, "$unknowns", false);
                        (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                    }
                }
                if (_end !== $undefined)
                    throw $Error("missing end group");
                return message;
            };

            /**
             * Creates an ExampleLoadout message from a plain object. Also converts values to their respective internal types.
             * @function fromObject
             * @memberof example_hook.v1.ExampleLoadout
             * @static
             * @param {Object.<string,*>} object Plain object
             * @returns {example_hook.v1.ExampleLoadout} ExampleLoadout
             */
            ExampleLoadout.fromObject = function (object, _depth) {
                if (object instanceof $root.example_hook.v1.ExampleLoadout)
                    return object;
                if (!$util.isObject(object))
                    throw $TypeError(".example_hook.v1.ExampleLoadout: object expected");
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let message = new $root.example_hook.v1.ExampleLoadout();
                if (object.weapon_id != null)
                    if ($Number(object.weapon_id) !== 0)
                        message.weapon_id = object.weapon_id >>> 0;
                if (object.perk_ids) {
                    if (!$Array.isArray(object.perk_ids))
                        throw $TypeError(".example_hook.v1.ExampleLoadout.perk_ids: array expected");
                    message.perk_ids = $Array(object.perk_ids.length);
                    for (let i = 0; i < object.perk_ids.length; ++i)
                        message.perk_ids[i] = object.perk_ids[i] >>> 0;
                }
                return message;
            };

            /**
             * Creates a plain object from an ExampleLoadout message. Also converts values to other types if specified.
             * @function toObject
             * @memberof example_hook.v1.ExampleLoadout
             * @static
             * @param {example_hook.v1.ExampleLoadout} message ExampleLoadout
             * @param {$protobuf.IConversionOptions} [options] Conversion options
             * @returns {Object.<string,*>} Plain object
             */
            ExampleLoadout.toObject = function (message, options, _depth) {
                if (!options)
                    options = {};
                if (_depth === $undefined)
                    _depth = 0;
                if (_depth > $util.recursionLimit)
                    throw $Error("max depth exceeded");
                let object = {};
                if (options.arrays || options.defaults)
                    object.perk_ids = [];
                if (options.defaults)
                    object.weapon_id = 0;
                if (message.weapon_id != null && $Object.hasOwnProperty.call(message, "weapon_id"))
                    object.weapon_id = message.weapon_id;
                if (message.perk_ids && message.perk_ids.length) {
                    object.perk_ids = $Array(message.perk_ids.length);
                    for (let j = 0; j < message.perk_ids.length; ++j)
                        object.perk_ids[j] = message.perk_ids[j];
                }
                return object;
            };

            /**
             * Converts this ExampleLoadout to JSON.
             * @function toJSON
             * @memberof example_hook.v1.ExampleLoadout
             * @instance
             * @returns {Object.<string,*>} JSON object
             */
            ExampleLoadout.prototype.toJSON = function() {
                return ExampleLoadout.toObject(this, $protobuf.util.toJSONOptions);
            };

            /**
             * Gets the type url for ExampleLoadout
             * @function getTypeUrl
             * @memberof example_hook.v1.ExampleLoadout
             * @static
             * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
             * @returns {string} The type url
             */
            ExampleLoadout.getTypeUrl = function(prefix) {
                if (prefix === $undefined)
                    prefix = "type.googleapis.com";
                return prefix + "/example_hook.v1.ExampleLoadout";
            };

            return ExampleLoadout;
        })();

        return v1;
    })();

    return example_hook;
})();

export {
  $root as default
};
