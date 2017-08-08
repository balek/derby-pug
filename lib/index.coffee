fs = require 'fs'

{Lexer} = require 'pug-lexer'
parse = require 'pug-parser'


class DerbyPugLexer extends Lexer
    each: ->
        # The only changed thing is first regex
        ```
            var captures;
            if (captures = /^(?:each|for) +([#a-zA-Z_$][\w$]*)(?: *, *([#a-zA-Z_$][\w$]*))? * in *([^\n]+)/.exec(this.input)) {
                this.consume(captures[0].length);
                var tok = this.tok('each', captures[1]);
                tok.key = captures[2] || null;
                this.incrementColumn(captures[0].length - captures[3].length);
                this.assertExpression(captures[3])
                tok.code = captures[3];
                this.incrementColumn(captures[3].length);
                this.tokens.push(tok);
                return true;
            }
            if (this.scan(/^(?:each|for)\b/)) {
                this.error('MALFORMED_EACH', 'malformed each');
            }
            if (captures = /^- *(?:each|for) +([a-zA-Z_$][\w$]*)(?: *, *([a-zA-Z_$][\w$]*))? +in +([^\n]+)/.exec(this.input)) {
                this.error(
                    'MALFORMED_EACH',
                    'Pug each and for should no longer be prefixed with a dash ("-"). They are pug keywords and not part of JavaScript.'
                );
            }
        ```
        return


isQuoted = (code, sym) ->
    code[0] == sym and code[code.length-1] == sym and sym not in code[1..-2]


module.exports = (app, opts) ->
    app.viewExtensions.push '.pug'
    app.compilers['.pug'] = new DerbyPugCompiler(opts).getCompileFunc()


class DerbyPugCompiler
    constructor: (@options = {}) ->
    getCompileFunc: -> @.compile.bind @

    compile: (file, fileName, preprocessOnly, jadeOptions) ->
        lexer = new DerbyPugLexer file, plugins: [
            isExpression: -> true
        ]
        ast = parse lexer.getTokens()
        views =
            for n in ast.nodes
                attrs =
                    for a in n.attrs
                        if a.val is true
                            a.name
                        else
                            "#{a.name}=#{a.val}"
                """
                    <#{n.name}: #{attrs.join ' '}>#{@compileBlock n.block, 1}
                """
        views.join '\n\n'


    compileCode: (code, attr) ->
        if @options.coffee
            coffee = require './coffee'
            return coffee code, attr

        if isQuoted code, '"'
            code
        else if isQuoted code, "'"
            '"' + code[1..-2] + '"'
        else if isQuoted code, '`'
            '"' + code[1..-2].replace(/\$\{/g, '{{').replace(/\}/g, '}}') + '"'
        else
            '"{{' + code + '}}"'


    compileBlock: (block, level) ->
        (@compileNode n, level for n in block.nodes).join ''


    compileNode: (node, level) ->
        offset = '  '.repeat level
        switch node.type
            when 'Tag', 'InterpolatedTag'
                if node.name in ['bound', 'unbound']
                    return """
                        #{offset}{{#{node.name}}
                        #{@compileBlock node.block, level+1}
                        #{offset}{{/#{node.name}}

                    """

                if node.name in ['with', 'on']
                    args = node.block.nodes.shift().val
                    parts = args.split ' as '
                    if parts.length > 2
                        raise 'Wrong format', args
                    parts[0] = @compileCode parts[0]
                    args = parts.join ' as '
                    return """

                        #{offset}{{#{node.name} #{args}}#{@compileBlock node.block, level+1}
                        #{offset}{{/#{node.name}}
                    """

                classes = []
                attrs =
                    for a in node.attrs
                        if a.name == 'class'
                            classes.push @compileCode(a.val, true)[1..-2]
                            continue
                        else if a.name.startsWith 'on-'
                            if a.val[0] in ["'", '"']
                                "#{a.name}=\"#{@compileCode a.val[1..-2]}\""
                            else
                                "#{a.name}=\"#{a.val}()\""
                        else if a.val is true
                            a.name
                        else
                            "#{a.name}=#{@compileCode a.val, true}"
                attrs.push "class=\"#{classes.join ' '}\"" if classes.length
                attrs = if attrs.length then ' ' + attrs.join ' ' else ''

                if node.expr
                    attrs = " is=#{@compileCode node.expr, true}" + attrs
                    node.name = 'tag'

                if node.selfClosing
                    "#{offset}<#{node.name}#{attrs}/>\n"
                else if not node.block.nodes.length or
                        node.block.nodes.length == 1 and node.block.nodes[0].type in ['Text', 'Code']
                    "\n#{offset}<#{node.name}#{attrs}>#{@compileBlock node.block, 0}</#{node.name}>"
                else
                    """

                        #{offset}<#{node.name}#{attrs}>#{@compileBlock node.block, level+1}
                        #{offset}</#{node.name}>
                    """

            when 'Code'
                if node.mustEscape
                    "{{ #{@compileCode node.val} }}"
                else
                    "{{ unescaped #{@compileCode node.val} }}"

            when 'Text'
                node.val

            when 'Each'
                vars =
                    if node.key
                        "#{node.val}, #{node.key}"
                    else
                        node.val
                """

                    #{offset}{{each #{node.obj} as #{vars}}}#{@compileBlock node.block, level+1}
                    #{offset}{{/each}}
                """

            when 'Conditional'
                @compileConditional node, level+1

            when 'BlockComment', 'Comment'
                return '' unless node.buffer
                """

                    #{offset}<!--#{node.val}
                    #{@compileBlock node.block, level+1}
                    #{offset}-->
                """

            when 'Comment'
                return '' unless node.buffer
                "\n#{offset}<!-- #{node.val} -->"

            else
                console.error 'Unknown Pug node', node


    compileConditional: (node, level) ->
        offset = '  '.repeat level
        code = """

            #{offset}{{if #{node.test}}}#{@compileBlock node.consequent, level+1}
        """
        n = node.alternate
        while n
            if n.type == 'Conditional'
                code += """

                    #{offset}{{else if #{node.test}}}#{@compileBlock node.consequent, level+1}
                """
            else
                code += """

                    #{offset}{{else}}#{@compileBlock node.consequent, level+1}
                """
            n = n.alternate
        code += "\n#{offset}{{/if}}"
