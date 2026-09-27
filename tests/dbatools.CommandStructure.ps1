function Get-DbaCommandStructureFinding {
    <#
    .SYNOPSIS
        Static checks for the command invariants in CLAUDE.md that the AST can prove.

    .DESCRIPTION
        Used by the "command structure" Describe in dbatools.Tests.ps1, and by its fixtures, which is
        why it lives in its own file. It needs no SQL Server and does not load the module.

        Rule 1: a Stop-Function call that can execute continue needs a local target - a loop or a
        switch in the same function or scriptblock, carrying the label when -ContinueLabel is used.
        Stop-Function continues with -Continue (default mode) and with -SilentlyContinue (under
        EnableException), so either switch requires the target. The search for the target stops at a
        function or scriptblock boundary: a loop around a helper definition or a callback is not proof,
        because the continue then binds to whatever loop is running when it executes.

        Rule 3: when begin can set the command's interrupt flag, process starts with
        if (Test-FunctionInterrupt) { return }. Stop-Function sets the flag in its caller's scope
        whenever it does not continue, which in the default mode means every call without -Continue,
        -SilentlyContinue alone included. A call counts when it runs in the command's own scope:
        directly in begin, or in a scriptblock that is dot-sourced or handed to ForEach-Object,
        Where-Object, .ForEach() or .Where(). A helper function, & { }, Invoke-Command and .Invoke()
        run in a new scope, so the flag they set never reaches Test-FunctionInterrupt. Any other way to
        run a scriptblock is reported for review, not assumed safe.

        A switch whose value cannot be read statically (-Continue:$variable, a splat that is not a
        hashtable literal in the same function) counts as set. Findings are objects with Rule, File,
        Function, Line and Message.

    .PARAMETER Ast
        The parsed file.

    .PARAMETER File
        The name to report the findings under.

    .PARAMETER StopFunctionParameter
        The parameters of Stop-Function: every name and alias as a key, the parameter name as its value.
        A call parameter is resolved the way PowerShell binds it - name, alias, then unique prefix - and
        one that resolves to nothing, or to more than one parameter, is reported, because that call
        fails with a parameter binding error.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)]
        [string]$File,
        [Parameter(Mandatory)]
        [hashtable]$StopFunctionParameter
    )

    # A call parameter as the Stop-Function parameter it binds to, or $null.
    $resolveParameter = {
        param($Name)
        if ($StopFunctionParameter.ContainsKey($Name)) { return $StopFunctionParameter[$Name] }
        $candidates = @($StopFunctionParameter.Keys | Where-Object { $PSItem.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $StopFunctionParameter[$PSItem] } | Select-Object -Unique)
        if ($candidates.Count -eq 1) { return $candidates[0] }
        return $null
    }

    $sameScopeCommands = @("ForEach-Object", "%", "foreach", "Where-Object", "?", "where")
    $newScopeCommands = @("Invoke-Command", "icm")

    # The innermost function around a node, or $null for top-level code.
    $getFunction = {
        param($Node)
        $parent = $Node.Parent
        while ($parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $parent }
            $parent = $parent.Parent
        }
        return $null
    }

    $getFunctionName = {
        param($Node)
        $function = & $getFunction $Node
        if ($function) { return $function.Name }
        return "<script>"
    }

    # How a scriptblock literal is run: "same" (the enclosing scope), "new" (a scope of its own) or
    # "unresolved" (anything the check does not know).
    $getInvocationScope = {
        param($ScriptBlockExpression)
        $parent = $ScriptBlockExpression.Parent
        if ($parent -is [System.Management.Automation.Language.CommandAst]) {
            if ($parent.CommandElements[0] -eq $ScriptBlockExpression) {
                if ($parent.InvocationOperator -eq "Dot") { return "same" }
                if ($parent.InvocationOperator -eq "Ampersand") { return "new" }
                return "unresolved"
            }
            $commandName = $parent.GetCommandName()
            if ($commandName -in $sameScopeCommands) { return "same" }
            if ($commandName -in $newScopeCommands) { return "new" }
            return "unresolved"
        }
        if ($parent -is [System.Management.Automation.Language.CommandParameterAst]) {
            $command = $parent.Parent
            if ($command.GetCommandName() -in $sameScopeCommands) { return "same" }
            if ($command.GetCommandName() -in $newScopeCommands) { return "new" }
            return "unresolved"
        }
        if ($parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $memberName = $parent.Member.Value
            if ($parent.Expression -eq $ScriptBlockExpression -and $memberName -in "Invoke", "InvokeReturnAsIs") { return "new" }
            if ($parent.Arguments -contains $ScriptBlockExpression -and $memberName -in "ForEach", "Where") { return "same" }
        }
        return "unresolved"
    }

    # The value of a hashtable entry or a switch argument: "true", "false" or "unknown".
    $getBooleanState = {
        param($ValueAst)
        $expression = $ValueAst
        if ($expression -is [System.Management.Automation.Language.PipelineAst] -and $expression.PipelineElements.Count -eq 1) {
            $expression = $expression.PipelineElements[0]
        }
        if ($expression -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $expression = $expression.Expression
        }
        if ($expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
            if ($expression.VariablePath.UserPath -eq "true") { return "true" }
            if ($expression.VariablePath.UserPath -eq "false") { return "false" }
        }
        return "unknown"
    }

    # The label text of a -ContinueLabel value, or "unknown".
    $getLabel = {
        param($ValueAst)
        $expression = $ValueAst
        if ($expression -is [System.Management.Automation.Language.PipelineAst] -and $expression.PipelineElements.Count -eq 1) {
            $expression = $expression.PipelineElements[0]
        }
        if ($expression -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $expression = $expression.Expression
        }
        if ($expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $expression.Value }
        return "unknown"
    }

    # The arguments of a Stop-Function call as a hashtable of parameter name to "true", "false",
    # "unknown" or, for -ContinueLabel, the label text. Missing keys are parameters not passed.
    $getStopFunctionArguments = {
        param($CommandAst)
        $arguments = New-Object -TypeName System.Collections.Hashtable
        $problems = @()
        $elements = $CommandAst.CommandElements
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                $splatName = $element.VariablePath.UserPath
                $scopeNode = & $getFunction $CommandAst
                if (-not $scopeNode) { $scopeNode = $Ast }
                $assignments = @($scopeNode.FindAll({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                            $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                            $Node.Left.VariablePath.UserPath -eq $splatName -and
                            $Node.Extent.StartOffset -lt $CommandAst.Extent.StartOffset
                        }, $true))
                $hashtable = $null
                if ($assignments) {
                    $right = $assignments[-1].Right
                    if ($right -is [System.Management.Automation.Language.CommandExpressionAst] -and $right.Expression -is [System.Management.Automation.Language.HashtableAst]) {
                        $hashtable = $right.Expression
                    }
                }
                if (-not $hashtable) {
                    $problems += "splat @$splatName is not a hashtable literal assigned earlier in the same function"
                    foreach ($name in "Continue", "SilentlyContinue", "ContinueLabel") { $arguments[$name] = "unknown" }
                    continue
                }
                foreach ($pair in $hashtable.KeyValuePairs) {
                    $key = & $resolveParameter $pair.Item1.Value
                    if (-not $key) {
                        $problems += "splat @$splatName has the key $($pair.Item1.Extent.Text), which binds to no Stop-Function parameter"
                        continue
                    }
                    if ($key -eq "ContinueLabel") {
                        $arguments[$key] = & $getLabel $pair.Item2
                    } else {
                        $arguments[$key] = & $getBooleanState $pair.Item2
                    }
                }
                continue
            }
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $name = & $resolveParameter $element.ParameterName
            if (-not $name) {
                $problems += "parameter -$($element.ParameterName) binds to no Stop-Function parameter, so the call fails"
                foreach ($switchName in "Continue", "SilentlyContinue") { $arguments[$switchName] = "unknown" }
                continue
            }
            if ($name -in "Continue", "SilentlyContinue") {
                if ($element.Argument) {
                    $arguments[$name] = & $getBooleanState $element.Argument
                } else {
                    $arguments[$name] = "true"
                }
            } elseif ($name -eq "ContinueLabel") {
                $labelValue = $element.Argument
                if (-not $labelValue -and $i -lt $elements.Count - 1) {
                    $i++
                    $labelValue = $elements[$i]
                }
                $arguments[$name] = & $getLabel $labelValue
            } elseif (-not $element.Argument -and $name -ne "OverrideExceptionMessage" -and $i -lt $elements.Count - 1 -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                # Every other parameter takes the next element as its value.
                $i++
            }
        }
        [PSCustomObject]@{
            Arguments = $arguments
            Problems  = $problems
        }
    }

    $newFinding = {
        param($Rule, $Node, $Message)
        [PSCustomObject]@{
            Rule     = $Rule
            File     = $File
            Function = & $getFunctionName $Node
            Line     = $Node.Extent.StartLineNumber
            Message  = $Message
        }
    }

    $stopCalls = @($Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq "Stop-Function"
            }, $true))

    $callInfo = New-Object -TypeName System.Collections.Hashtable
    foreach ($call in $stopCalls) {
        $parsed = & $getStopFunctionArguments $call
        $callInfo[$call] = $parsed.Arguments
        foreach ($problem in $parsed.Problems) {
            & $newFinding "Arguments" $call "Stop-Function cannot be checked: $problem"
        }
    }

    #region Rule 1
    foreach ($call in $stopCalls) {
        $arguments = $callInfo[$call]
        $mayContinue = $arguments["Continue"] -in "true", "unknown" -or $arguments["SilentlyContinue"] -in "true", "unknown"
        if (-not $mayContinue) { continue }

        $label = $arguments["ContinueLabel"]
        if ($label -eq "unknown") {
            & $newFinding "1" $call "Stop-Function can continue, and its -ContinueLabel target cannot be read statically"
            continue
        }

        $hasTarget = $false
        $parent = $call.Parent
        while ($parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst] -or $parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { break }
            if ($parent -is [System.Management.Automation.Language.LoopStatementAst] -or $parent -is [System.Management.Automation.Language.SwitchStatementAst]) {
                if (-not $label -or $parent.Label -eq $label) {
                    $hasTarget = $true
                    break
                }
            }
            $parent = $parent.Parent
        }
        if ($hasTarget) { continue }

        if ($label) {
            $message = "Stop-Function can continue, and no loop or switch labeled :$label encloses it in the same function or scriptblock"
        } else {
            $message = "Stop-Function can continue, and no loop or switch encloses it in the same function or scriptblock"
        }
        & $newFinding "1" $call $message
    }
    #endregion Rule 1

    #region Rule 3
    $isGuard = {
        param($Statement)
        if ($Statement -isnot [System.Management.Automation.Language.IfStatementAst]) { return $false }
        if ($Statement.Clauses.Count -ne 1 -or $Statement.ElseClause) { return $false }
        $condition = $Statement.Clauses[0].Item1
        $body = $Statement.Clauses[0].Item2
        if ($condition -isnot [System.Management.Automation.Language.PipelineAst] -or $condition.PipelineElements.Count -ne 1) { return $false }
        $conditionCommand = $condition.PipelineElements[0]
        if ($conditionCommand -isnot [System.Management.Automation.Language.CommandAst] -or $conditionCommand.GetCommandName() -ne "Test-FunctionInterrupt") { return $false }
        if ($body.Statements.Count -ne 1) { return $false }
        $returnStatement = $body.Statements[0]
        return ($returnStatement -is [System.Management.Automation.Language.ReturnStatementAst] -and -not $returnStatement.Pipeline)
    }

    $functions = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    foreach ($function in $functions) {
        $beginBlock = $function.Body.BeginBlock
        if (-not $beginBlock) { continue }

        $flagCalls = @()
        foreach ($call in $stopCalls) {
            if ($callInfo[$call]["Continue"] -eq "true") { continue }

            # Walk up to the begin block and decide in which scope the call runs. A nested function
            # on the way means a scope of its own; a scriptblock depends on how it is run.
            $scope = "same"
            $insideBegin = $false
            $parent = $call.Parent
            while ($parent) {
                if ($parent -eq $beginBlock) {
                    $insideBegin = $true
                    break
                }
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }
                if ($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $scope -eq "same") {
                    $scope = & $getInvocationScope $parent
                }
                $parent = $parent.Parent
            }
            if (-not $insideBegin -or $scope -eq "new") { continue }

            if ($scope -eq "unresolved") {
                & $newFinding "3" $call "Stop-Function in begin runs in a scriptblock whose scope the check cannot determine; review whether it can set the interrupt flag of $($function.Name)"
                continue
            }
            $flagCalls += $call
        }
        if (-not $flagCalls) { continue }

        $flagLine = $flagCalls[0].Extent.StartLineNumber
        $processBlock = $function.Body.ProcessBlock
        if (-not $processBlock) {
            & $newFinding "3" $flagCalls[0] "begin of $($function.Name) can set the interrupt flag (line $flagLine), and there is no process block to guard"
            continue
        }

        $statements = $processBlock.Statements
        if ($statements.Count -gt 0 -and (& $isGuard $statements[0])) { continue }

        $laterGuard = @($statements | Where-Object { & $isGuard $PSItem })
        if ($laterGuard) {
            $message = "begin of $($function.Name) can set the interrupt flag (line $flagLine), and the process guard is not the first statement (line $($laterGuard[0].Extent.StartLineNumber))"
        } else {
            $message = "begin of $($function.Name) can set the interrupt flag (line $flagLine), and process does not start with if (Test-FunctionInterrupt) { return }"
        }
        & $newFinding "3" $processBlock $message
    }
    #endregion Rule 3
}

function Get-DbaStopFunctionParameterMap {
    <#
    .SYNOPSIS
        Every parameter name and alias of Stop-Function, mapped to the parameter name, read from its
        source so the checks follow the function when it changes.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stopFunctionAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $definition = $stopFunctionAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq "Stop-Function" }, $true)
    # Parameter names are case-insensitive; a Hashtable from New-Object is not, unlike @{ }.
    $map = New-Object -TypeName System.Collections.Hashtable -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($parameter in $definition.Body.ParamBlock.Parameters) {
        $parameterName = $parameter.Name.VariablePath.UserPath
        $map[$parameterName] = $parameterName
        foreach ($attribute in ($parameter.Attributes | Where-Object { $PSItem.TypeName.Name -eq "Alias" })) {
            foreach ($alias in $attribute.PositionalArguments) {
                $map[$alias.Value] = $parameterName
            }
        }
    }
    $map
}
