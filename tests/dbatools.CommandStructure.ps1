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
        run a scriptblock is reported for review, not assumed safe. A call with -Continue counts too
        when a try with a catch, or a trap, in begin encloses it and EnableException is not $false:
        Stop-Function then sets the flag and throws, and begin goes on after the catch. The guard counts
        only in the exact shape if (Test-FunctionInterrupt) { return }, without arguments or
        redirections.

        A switch whose value cannot be read statically (-Continue:$variable, a splat whose value at the
        call is not certain) counts as set. A splat is resolved only from a single hashtable literal that
        certainly reaches the call and is never changed; see $resolveSplat. Findings are objects with
        Rule, File, Function, Line and Message.

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

    # A variable name without its scope qualifier, so $script:splat and $splat count as one name.
    $getVariableName = {
        param($VariableAst)
        $VariableAst.VariablePath.UserPath -replace "^(global|local|private|script|using|variable):", ""
    }

    $variableCommands = @("Set-Variable", "sv", "set", "New-Variable", "nv", "Remove-Variable", "rv", "Clear-Variable", "clv", "Get-Variable", "gv", "Invoke-Expression", "iex")

    # Whether Inner lies within the source text of Outer.
    $isWithin = {
        param($Inner, $Outer)
        $Inner.Extent.StartOffset -ge $Outer.Extent.StartOffset -and $Inner.Extent.EndOffset -le $Outer.Extent.EndOffset
    }

    # The hashtable literal a splat of a Stop-Function call is built from, as an object with Hashtable
    # (the HashtableAst, or $null) and Reason (why it cannot be resolved). An unresolved splat counts
    # as setting every switch. The splat is resolved only from the assignment that certainly reaches
    # the call with nothing able to change the value in between:
    # - The definition is the last assignment of the variable before the call in the function, a plain
    #   $name = @{ } at statement level of a block that encloses the call. A scriptblock between the
    #   block and the call must be one whose invocation the check knows.
    # - Every other use of the variable that can change it (an assignment, a key assignment, a method
    #   call, [ref], ++, handing the hashtable to a command or another variable) is a write. Only
    #   splatting it, reading a key and expanding it in a string are reads. No write may lie between
    #   the definition and the end of the call, none in a loop or scriptblock between the block and the
    #   call (the next iteration runs it before the call), and none in a nested function or scriptblock
    #   that does not enclose the definition (it can run between the two).
    # - No variable cmdlet names the variable or a name the check cannot read, no Invoke-Expression,
    #   and the name is no command argument (such as -OutVariable).
    $resolveSplat = {
        param($CommandAst, $SplatName)
        $unresolved = {
            param($Reason)
            [PSCustomObject]@{
                Hashtable = $null
                Reason    = $Reason
            }
        }

        $scopeNode = & $getFunction $CommandAst
        if (-not $scopeNode) { $scopeNode = $Ast }

        $uses = @($scopeNode.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and (& $getVariableName $Node) -eq $SplatName
                }, $true))
        $writes = @(foreach ($use in $uses) {
                if ($use.Splatted) { continue }
                $useParent = $use.Parent
                if ($useParent -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { continue }
                $isRead = $false
                if ($useParent -is [System.Management.Automation.Language.MemberExpressionAst] -and $useParent -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $useParent.Expression -eq $use) { $isRead = $true }
                if ($useParent -is [System.Management.Automation.Language.IndexExpressionAst] -and $useParent.Target -eq $use) { $isRead = $true }
                if ($isRead -and $useParent.Parent -is [System.Management.Automation.Language.UnaryExpressionAst] -and $useParent.Parent.TokenKind -in "PlusPlus", "MinusMinus", "PostfixPlusPlus", "PostfixMinusMinus") { $isRead = $false }
                if ($isRead) {
                    # A key read on the left of an assignment is a key assignment.
                    $assignment = $useParent.Parent
                    while ($assignment -and $assignment -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { $assignment = $assignment.Parent }
                    if ($assignment -and (& $isWithin $use $assignment.Left)) { $isRead = $false }
                }
                if (-not $isRead) { $use }
            })

        $assignments = @($scopeNode.FindAll({
                    param($Node)
                    if ($Node -isnot [System.Management.Automation.Language.AssignmentStatementAst] -or $Node.Extent.StartOffset -ge $CommandAst.Extent.StartOffset) { return $false }
                    foreach ($write in $writes) {
                        if (& $isWithin $write $Node.Left) { return $true }
                    }
                    return $false
                }, $true) | Sort-Object -Property { $PSItem.Extent.StartOffset })
        if (-not $assignments) {
            return (& $unresolved "splat @$SplatName is not assigned before the call in the same function")
        }

        $definition = $assignments[-1]
        $right = $definition.Right
        $isPlain = $definition.Operator -eq "Equals" -and
        $definition.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $definition.Left.VariablePath.UserPath -eq $SplatName
        if (-not $isPlain) {
            return (& $unresolved "splat @$SplatName is changed at line $($definition.Extent.StartLineNumber) before the call")
        }
        if ($right -isnot [System.Management.Automation.Language.CommandExpressionAst] -or $right.Expression -isnot [System.Management.Automation.Language.HashtableAst]) {
            return (& $unresolved "splat @$SplatName is not assigned a hashtable literal at line $($definition.Extent.StartLineNumber), its last assignment before the call")
        }

        # The assignment reaches the call only when it is a statement of a block that encloses the call
        # and comes first. Loops and scriptblocks between the block and the call are collected, because
        # they can run a write after the call and then the call again.
        $definitionBlock = $definition.Parent
        $reaches = $false
        $repeated = @()
        if ($definition.Extent.EndOffset -le $CommandAst.Extent.StartOffset -and ($definitionBlock -is [System.Management.Automation.Language.StatementBlockAst] -or $definitionBlock -is [System.Management.Automation.Language.NamedBlockAst])) {
            $parent = $CommandAst.Parent
            while ($parent) {
                if ($parent -eq $definitionBlock) {
                    $reaches = $true
                    break
                }
                if ($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    if ((& $getInvocationScope $parent) -eq "unresolved") { break }
                    $repeated += $parent
                }
                if ($parent -is [System.Management.Automation.Language.LoopStatementAst]) { $repeated += $parent }
                $parent = $parent.Parent
            }
        }
        if (-not $reaches) {
            return (& $unresolved "splat @$SplatName is last assigned at line $($definition.Extent.StartLineNumber) in a branch, loop, try or scriptblock the call is not part of, so the assignment is not certain to reach the call")
        }

        $nestedBodies = @($scopeNode.FindAll({
                    param($Node)
                    ($Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or $Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) -and $Node -ne $scopeNode -and -not (& $isWithin $definition $Node)
                }, $true))
        foreach ($write in $writes) {
            if ($write -eq $definition.Left) { continue }
            $between = $write.Extent.StartOffset -ge $definition.Extent.EndOffset -and $write.Extent.StartOffset -lt $CommandAst.Extent.EndOffset
            $inRepeated = @($repeated | Where-Object { & $isWithin $write $PSItem }).Count -gt 0
            $inNested = @($nestedBodies | Where-Object { & $isWithin $write $PSItem }).Count -gt 0
            if ($between -or $inRepeated -or $inNested) {
                return (& $unresolved "splat @$SplatName can be changed at line $($write.Extent.StartLineNumber) after its assignment at line $($definition.Extent.StartLineNumber) and before the call")
            }
        }

        $variableCommandCalls = @($scopeNode.FindAll({
                    param($Node)
                    if ($Node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                    $commandName = $Node.GetCommandName()
                    if ($commandName -in "Invoke-Expression", "iex") { return $true }
                    if ($commandName -notin $variableCommands) { return $false }
                    # The name is the argument of -Name, or else the first positional argument.
                    $elements = $Node.CommandElements
                    $nameValue = $null
                    for ($i = 1; $i -lt $elements.Count; $i++) {
                        $element = $elements[$i]
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                            if ("Name".StartsWith($element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $nameValue = $element.Argument
                                if (-not $nameValue -and $i -lt $elements.Count - 1) { $nameValue = $elements[$i + 1] }
                                break
                            }
                            if (-not $element.Argument) { $i++ }
                            continue
                        }
                        $nameValue = $element
                        break
                    }
                    if ($nameValue -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $true }
                    return ($nameValue.Value -eq $SplatName)
                }, $true))
        if ($variableCommandCalls) {
            return (& $unresolved "splat @$SplatName can be changed by $($variableCommandCalls[0].GetCommandName()) at line $($variableCommandCalls[0].Extent.StartLineNumber)")
        }

        # The name as a command argument, such as -OutVariable splatStop, can write the variable too.
        $nameArguments = @($scopeNode.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $Node.Value -eq $SplatName -and ($Node.Parent -is [System.Management.Automation.Language.CommandAst] -or $Node.Parent -is [System.Management.Automation.Language.CommandParameterAst])
                }, $true))
        if ($nameArguments) {
            return (& $unresolved "splat @$SplatName is named as a command argument at line $($nameArguments[0].Extent.StartLineNumber), which can write it")
        }

        [PSCustomObject]@{
            Hashtable = $right.Expression
            Reason    = $null
        }
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
                $splatName = & $getVariableName $element
                $resolvedSplat = & $resolveSplat $CommandAst $splatName
                if (-not $resolvedSplat.Hashtable) {
                    $problems += $resolvedSplat.Reason
                    foreach ($name in "Continue", "SilentlyContinue", "ContinueLabel", "EnableException") { $arguments[$name] = "unknown" }
                    continue
                }
                foreach ($pair in $resolvedSplat.Hashtable.KeyValuePairs) {
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
            } elseif ($name -eq "EnableException") {
                # A [bool], so the value is the colon argument or the next element.
                $enableValue = $element.Argument
                if (-not $enableValue -and $i -lt $elements.Count - 1 -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    $i++
                    $enableValue = $elements[$i]
                }
                if ($enableValue) {
                    $arguments[$name] = & $getBooleanState $enableValue
                } else {
                    $arguments[$name] = "unknown"
                }
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
        # Only the bare call returns its result to the condition: a redirection such as > $null discards
        # the $true, and an argument fails the call, so both leave the condition false.
        if ($conditionCommand.CommandElements.Count -ne 1 -or $conditionCommand.Redirections.Count -ne 0 -or $conditionCommand.InvocationOperator -ne "Unknown") { return $false }
        if ($condition.PSObject.Properties["Background"] -and $condition.Background) { return $false }
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
            # -Continue sets the flag only on its throwing path: under EnableException, without
            # -SilentlyContinue, Stop-Function sets the flag and throws. That matters only when begin
            # can catch the exception and go on, so such a call counts when a try with a catch, or a
            # trap, in begin encloses it. EnableException counts as possible unless it is $false,
            # because Stop-Function takes the value of the caller when it is not passed.
            $arguments = $callInfo[$call]
            $continueOnly = $arguments["Continue"] -eq "true"
            if ($continueOnly -and ($arguments["SilentlyContinue"] -eq "true" -or $arguments["EnableException"] -eq "false")) { continue }

            # Walk up to the begin block and decide in which scope the call runs. A nested function
            # on the way means a scope of its own; a scriptblock depends on how it is run.
            $scope = "same"
            $insideBegin = $false
            $canResume = $false
            $parent = $call.Parent
            while ($parent) {
                if ($parent -eq $beginBlock) {
                    $insideBegin = $true
                    if ($parent.Traps) { $canResume = $true }
                    break
                }
                if ($parent -is [System.Management.Automation.Language.TryStatementAst] -and $parent.CatchClauses.Count -gt 0 -and $call.Extent.StartOffset -ge $parent.Body.Extent.StartOffset -and $call.Extent.EndOffset -le $parent.Body.Extent.EndOffset) {
                    $canResume = $true
                }
                if ($parent -is [System.Management.Automation.Language.StatementBlockAst] -and $parent.Traps) { $canResume = $true }
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }
                if ($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $scope -eq "same") {
                    $scope = & $getInvocationScope $parent
                }
                $parent = $parent.Parent
            }
            if (-not $insideBegin -or $scope -eq "new") { continue }
            if ($continueOnly -and -not $canResume) { continue }

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
