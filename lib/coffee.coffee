CoffeeScript = require 'coffeescript'

{Lexer} = require 'coffeescript/lib/coffeescript/lexer'
{IdentifierLiteral, Block, Base} = require 'coffeescript/lib/coffeescript/nodes'
{Scope} = require 'coffeescript/lib/coffeescript/scope'


# Support for alias paths in expressions
# Can't use inheritance, because Lexer::matchWithInterpolations uses original Lexer
Lexer::_commentToken  = Lexer::commentToken
Lexer::commentToken = ->
    return 0 if Lexer::derbyMode
    @_commentToken()


Lexer::_identifierToken = Lexer::identifierToken
Lexer::identifierToken = ->
    if Lexer::derbyMode and @chunk.startsWith '#'
        @chunk = 'A' + @chunk[1..]
        len = @_identifierToken()
        lastToken = @tokens[@tokens.length-1]
        lastToken[1] = '#' + lastToken[1][1..]
        return len
    @_identifierToken()


# This hack is used to pass multiple function for `on-` attributes
Block::joinFragmentArrays = (fragmentsList, joinStr) ->
    if joinStr == ', ' and @level == 2
        joinStr = '; '
    Base::joinFragmentArrays.call this, fragmentsList, joinStr


module.exports = (code, isAttr) ->
    Lexer::derbyMode = true
    node = CoffeeScript.nodes code
    Lexer::derbyMode = false

    node.traverseChildren true, (n) ->
        switch n.constructor.name
            when 'StringLiteral'
                # Make all internal string literals quoted with single quote
                n.value = "'#{n.value[1..-2]}'"
            when 'If'
                # Switch default `else` value to empty string
                if not n.elseBody
                    n.elseBody = CoffeeScript.nodes "''"
            when 'Value'
                switch n.base.constructor.name
                    when 'UndefinedLiteral'
                        # Prevent compilation to `void 0`
                        n.base = new IdentifierLiteral 'undefined'
                    when 'ThisLiteral'
                        # Support for attribute paths
                        attr = n.properties.shift()
                        n.base = new IdentifierLiteral '@' + attr.name.value
                    when 'StringWithInterpolations'
                        # Prevent compilation to ES6 template string
                        n.base = n.base.body.expressions[0]

        true

    if isAttr
        if node.expressions?.length == 1 and
                node.expressions[0].base?.constructor.name == 'StringLiteral'
            base = node.expressions[0].base
            base.value = "\"#{base.value[1..-2]}\""
        else
            wrap = true

    code = node.compileNode
            indent: ''
            level: 2
            scope: new Scope null, this, null, []
        .map (n) -> n.code
        .join ''

    # Coffee compiles objects to multiple lines
    code = code.replace /\n/g, ' '

    if wrap
        return "\"{{ #{code} }}\""
    code
