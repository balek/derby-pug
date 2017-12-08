CoffeeScript = require 'coffee-script'

{Lexer} = require 'coffee-script/lib/coffee-script/lexer'
{IdentifierLiteral, Block, Base} = require 'coffee-script/lib/coffee-script/nodes'


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
                if n.base.constructor.name == 'ThisLiteral'
                    # Support for attribute paths
                    attr = n.properties.shift()
                    n.base = new IdentifierLiteral '@' + attr.name.value
        true

    if isAttr
        if node.expressions?.length == 1 and
                node.expressions[0].base?.constructor.name == 'StringLiteral'
            base = node.expressions[0].base
            base.value = "\"#{base.value[1..-2]}\""
        else
            wrap = true

    code = node.compileNode(indent: '', level: 2).map((n) -> n.code).join ''

    # Coffee compiles objects to multiple lines
    code = code.replace /\n/g, ' '

    if wrap
        return "\"{{ #{code} }}\""
    code
