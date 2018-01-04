if (-not (Get-Command -Name Register-ArgumentCompleter -ErrorAction Ignore))
{

    #############################################################################
    #
    # TabExpansionPlusPlus
    #
    #

<#
Copyright (c) 2013, Jason Shirk
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#>

    # Save off the previous tab completion so it can be restored if this module
    # is removed.
    $oldTabExpansion = $function:TabExpansion
    $oldTabExpansion2 = $function:TabExpansion2

    [bool]$updatedTypeData = $false


    #region Exported utility functions for completers

    #############################################################################
    #
    # Helper function to create a new completion results
    #
    function New-CompletionResult
    {
        param ([Parameter(Position = 0, ValueFromPipelineByPropertyName, Mandatory, ValueFromPipeline)]
            [ValidateNotNullOrEmpty()]
            [string]
            $CompletionText,

            [Parameter(Position = 1, ValueFromPipelineByPropertyName)]
            [string]
            $ToolTip,

            [Parameter(Position = 2, ValueFromPipelineByPropertyName)]
            [string]
            $ListItemText,

            [System.Management.Automation.CompletionResultType]
            $CompletionResultType = [System.Management.Automation.CompletionResultType]::ParameterValue,

            [Parameter(Mandatory = $false)]
            [switch]
            $NoQuotes = $false
        )

        process
        {
            $toolTipToUse = if ($ToolTip -eq '') { $CompletionText }
            else { $ToolTip }
            $listItemToUse = if ($ListItemText -eq '') { $CompletionText }
            else { $ListItemText }

            # If the caller explicitly requests that quotes
            # not be included, via the -NoQuotes parameter,
            # then skip adding quotes.

            if ($CompletionResultType -eq [System.Management.Automation.CompletionResultType]::ParameterValue -and -not $NoQuotes)
            {
                # Add single quotes for the caller in case they are needed.
                # We use the parser to robustly determine how it will treat
                # the argument.  If we end up with too many tokens, or if
                # the parser found something expandable in the results, we
                # know quotes are needed.

                $tokens = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput("echo $CompletionText", [ref]$tokens, [ref]$null)
                if ($tokens.Length -ne 3 -or
                    ($tokens[1] -is [System.Management.Automation.Language.StringExpandableToken] -and
                        $tokens[1].Kind -eq [System.Management.Automation.Language.TokenKind]::Generic))
                {
                    $CompletionText = "'$CompletionText'"
                }
            }
            return New-Object System.Management.Automation.CompletionResult `
            ($CompletionText, $listItemToUse, $CompletionResultType, $toolTipToUse.Trim())
        }

    }

    #############################################################################
    #
    # .SYNOPSIS
    #
    #     This is a simple wrapper of Get-Command gets commands with a given
    #     parameter ignoring commands that use the parameter name as an alias.
    #
    function Get-CommandWithParameter
    {
        [CmdletBinding(DefaultParameterSetName = 'AllCommandSet')]
        param (
            [Parameter(ParameterSetName = 'AllCommandSet', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${Name},

            [Parameter(ParameterSetName = 'CmdletSet', ValueFromPipelineByPropertyName)]
            [string[]]
            ${Verb},

            [Parameter(ParameterSetName = 'CmdletSet', ValueFromPipelineByPropertyName)]
            [string[]]
            ${Noun},

            [Parameter(ValueFromPipelineByPropertyName)]
            [string[]]
            ${Module},

            [ValidateNotNullOrEmpty()]
            [Parameter(Mandatory)]
            [string]
            ${ParameterName})

        begin
        {
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-Command', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd @PSBoundParameters | Where-Object { $_.Parameters[$ParameterName] -ne $null } }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)
        }
        process
        {
            $steppablePipeline.Process($_)
        }
        end
        {
            $steppablePipeline.End()
        }
    }

    #############################################################################
    #
    function Set-CompletionPrivateData
    {
        param (
            [ValidateNotNullOrEmpty()]
            [string]
            $Key,

            [object]
            $Value,

            [ValidateNotNullOrEmpty()]
            [int]
            $ExpirationSeconds = 604800
        )

        $Cache = [PSCustomObject]@{
            Value = $Value
            ExpirationTime = (Get-Date).AddSeconds($ExpirationSeconds)
        }
        $completionPrivateData[$key] = $Cache
    }

    #############################################################################
    #
    function Get-CompletionPrivateData
    {
        param (
            [ValidateNotNullOrEmpty()]
            [string]
            $Key)

        if (!$Key)
        { return $completionPrivateData }

        $cacheValue = $completionPrivateData[$key]
        if ((Get-Date) -lt $cacheValue.ExpirationTime)
        {
            return $cacheValue.Value
        }
    }

    #############################################################################
    #
    function Get-CompletionWithExtension
    {
        param ([string]
            $lastWord,

            [string[]]
            $extensions)

        [System.Management.Automation.CompletionCompleters]::CompleteFilename($lastWord) |
        Where-Object {
            # Use ListItemText because it won't be quoted, CompletionText might be
            [System.IO.Path]::GetExtension($_.ListItemText) -in $extensions
        }
    }

    #############################################################################
    #
    function New-CommandTree
    {
        [CmdletBinding(DefaultParameterSetName = 'Default')]
        param (
            [Parameter(Position = 0, Mandatory, ParameterSetName = 'Default')]
            [Parameter(Position = 0, Mandatory, ParameterSetName = 'Argument')]
            [ValidateNotNullOrEmpty()]
            [string]
            $Completion,

            [Parameter(Position = 1, Mandatory, ParameterSetName = 'Default')]
            [Parameter(Position = 1, Mandatory, ParameterSetName = 'Argument')]
            [string]
            $Tooltip,

            [Parameter(ParameterSetName = 'Argument')]
            [switch]
            $Argument,

            [Parameter(Position = 2, ParameterSetName = 'Default')]
            [Parameter(Position = 1, ParameterSetName = 'ScriptBlockSet')]
            [scriptblock]
            $SubCommands,

            [Parameter(Position = 0, Mandatory, ParameterSetName = 'ScriptBlockSet')]
            [scriptblock]
            $CompletionGenerator
        )

        $actualSubCommands = $null
        if ($null -ne $SubCommands)
        {
            $actualSubCommands = [NativeCommandTreeNode[]](& $SubCommands)
        }

        switch ($PSCmdlet.ParameterSetName)
        {
            'Default' {
                New-Object NativeCommandTreeNode $Completion, $Tooltip, $actualSubCommands
                break
            }
            'Argument' {
                New-Object NativeCommandTreeNode $Completion, $Tooltip, $true
            }
            'ScriptBlockSet' {
                New-Object NativeCommandTreeNode $CompletionGenerator, $actualSubCommands
                break
            }
        }
    }

    #############################################################################
    #
    function Get-CommandTreeCompletion
    {
        param ($wordToComplete,

            $commandAst,

            [NativeCommandTreeNode[]]
            $CommandTree)

        $commandElements = $commandAst.CommandElements

        # Skip the first command element - it's the command name
        # Iterate through the remaining elements, stopping early
        # if we find the element that matches $wordToComplete.
        for ($i = 1; $i -lt $commandElements.Count; $i++)
        {
            if (!($commandElements[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst]))
            {
                # Ignore arguments that are expressions.  In some rare cases this
                # could cause strange completions because the context is incorrect, e.g.:
                #    $c = 'advfirewall'
                #    netsh $c firewall
                # Here we would be in advfirewall firewall context, but we'd complete as
                # though we were in firewall context.
                continue
            }

            if ($commandElements[$i].Value -eq $wordToComplete)
            {
                $CommandTree = $CommandTree |
                Where-Object { $_.Command -like "$wordToComplete*" -or $_.CompletionGenerator -ne $null }
                break
            }

            foreach ($subCommand in $CommandTree)
            {
                if ($subCommand.Command -eq $commandElements[$i].Value)
                {
                    if (!$subCommand.Argument)
                    {
                        $CommandTree = $subCommand.SubCommands
                    }
                    break
                }
            }
        }

        if ($null -ne $CommandTree)
        {
            $CommandTree | ForEach-Object {
                if ($_.Command)
                {
                    $toolTip = if ($_.Tooltip) { $_.Tooltip }
                    else { $_.Command }
                    New-CompletionResult -CompletionText $_.Command -ToolTip $toolTip
                }
                else
                {
                    & $_.CompletionGenerator $wordToComplete $commandAst
                }
            }
        }
    }

    #endregion Exported utility functions for completers

    #region Exported functions

    #############################################################################
    #
    # .SYNOPSIS
    #     Register a ScriptBlock to perform argument completion for a
    #     given command or parameter.
    #
    # .DESCRIPTION
    #     Argument completion can be extended without needing to do any
    #     parsing in many cases. By registering a handler for specific
    #     commands and/or parameters, PowerShell will call the handler
    #     when appropriate.
    #
    #     There are 2 kinds of extensions - native and PowerShell. Native
    #     refers to commands external to PowerShell, e.g. net.exe. PowerShell
    #     completion covers any functions, scripts, or cmdlets where PowerShell
    #     can determine the correct parameter being completed.
    #
    #     When registering a native handler, you must specify the CommandName
    #     parameter. The CommandName is typically specified without any path
    #     or extension. If specifying a path and/or an extension, completion
    #     will only work when the command is specified that way when requesting
    #     completion.
    #
    #     When registering a PowerShell handler, you must specify the
    #     ParameterName parameter. The CommandName is optional - PowerShell will
    #     first try to find a handler based on the command and parameter, but
    #     if none is found, then it will try just the parameter name. This way,
    #     you could specify a handler for all commands that have a specific
    #     parameter.
    #
    #     A handler needs to return instances of
    #     System.Management.Automation.CompletionResult.
    #
    #     A native handler is passed 2 parameters:
    #
    #         param($wordToComplete, $commandAst)
    #
    #     $wordToComplete  - The argument being completed, possibly an empty string
    #     $commandAst      - The ast of the command being completed.
    #
    #     A PowerShell handler is passed 5 parameters:
    #
    #         param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    #
    #     $commandName        - The command name
    #     $parameterName      - The parameter name
    #     $wordToComplete     - The argument being completed, possibly an empty string
    #     $commandAst         - The parsed representation of the command being completed.
    #     $fakeBoundParameter - Like $PSBoundParameters, contains values for some of the parameters.
    #                           Certain values are not included, this does not mean a parameter was
    #                           not specified, just that getting the value could have had unintended
    #                           side effects, so no value was computed.
    #
    # .PARAMETER ParameterName
    #     The name of the parameter that the Completion parameter supports.
    #     This parameter is not supported for native completion and is
    #     mandatory for script completion.
    #
    # .PARAMETER CommandName
    #     The name of the command that the Completion parameter supports.
    #     This parameter is mandatory for native completion and is optional
    #     for script completion.
    #
    # .PARAMETER Completion
    #     A ScriptBlock that returns instances of CompletionResult. For
    #     native completion, the script block parameters are
    #
    #         param($wordToComplete, $commandAst)
    #
    #     For script completion, the parameters are:
    #
    #         param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    #
    # .PARAMETER Description
    #     A description of how the completion can be used.
    #
    function Register-ArgumentCompleter
    {
        [CmdletBinding(DefaultParameterSetName = "PowerShellSet")]
        param (
            [Parameter(ParameterSetName = "NativeSet", Mandatory)]
            [Parameter(ParameterSetName = "PowerShellSet")]
            [string[]]
            $CommandName = "",

            [Parameter(ParameterSetName = "PowerShellSet", Mandatory)]
            [string]
            $ParameterName = "",

            [Parameter(Mandatory)]
            [scriptblock]
            $ScriptBlock,

            [string]
            $Description,

            [Parameter(ParameterSetName = "NativeSet")]
            [switch]
            $Native)

        $fnDefn = $ScriptBlock.Ast -as [System.Management.Automation.Language.FunctionDefinitionAst]
        if (!$Description)
        {
            # See if the script block is really a function, if so, use the function name.
            $Description = if ($fnDefn -ne $null) { $fnDefn.Name }
            else { "" }
        }

        if ($MyInvocation.ScriptName -ne (& { $MyInvocation.ScriptName }))
        {
            # Make an unbound copy of the script block so it has access to TabExpansionPlusPlus when invoked.
            # We can skip this step if we created the script block (Register-ArgumentCompleter was
            # called internally).
            if ($fnDefn -ne $null)
            {
                $ScriptBlock = $ScriptBlock.Ast.Body.GetScriptBlock() # Don't reparse, just get a new ScriptBlock.
            }
            else
            {
                $ScriptBlock = $ScriptBlock.Ast.GetScriptBlock() # Don't reparse, just get a new ScriptBlock.
            }
        }

        foreach ($command in $CommandName)
        {
            if ($command -and $ParameterName)
            {
                $command += ":"
            }

            $key = if ($Native) { 'NativeArgumentCompleters' }
            else { 'CustomArgumentCompleters' }
            $tabExpansionOptions[$key]["${command}${ParameterName}"] = $ScriptBlock

            $tabExpansionDescriptions["${command}${ParameterName}$Native"] = $Description
        }
    }

    #############################################################################
    #
    # .SYNOPSIS
    #     Tests the registered argument completer
    #
    # .DESCRIPTION
    #     Invokes the registered parameteter completer for a specified command to make it easier to test
    #     a completer
    #
    # .EXAMPLE
    #  Test-ArgumentCompleter -CommandName Get-Verb -ParameterName Verb -WordToComplete Sta
    #
    # Test what would be completed if Get-Verb -Verb Sta<Tab> was typed at the prompt
    #
    # .EXAMPLE
    #  Test-ArgumentCompleter -NativeCommand Robocopy -WordToComplete /
    #
    # Test what would be completed if Robocopy /<Tab> was typed at the prompt
    #
    function Test-ArgumentCompleter
    {
        [CmdletBinding(DefaultParametersetName = 'PS')]
        param
        (
            [Parameter(Mandatory, Position = 1, ParameterSetName = 'PS')]
            [string]
            $CommandName
             ,

            [Parameter(Mandatory, Position = 2, ParameterSetName = 'PS')]
            [string]
            $ParameterName
             ,

            [Parameter(ParameterSetName = 'PS')]
            [System.Management.Automation.Language.CommandAst]
            $commandAst
             ,

            [Parameter(ParameterSetName = 'PS')]
            [Hashtable]
            $FakeBoundParameters = @{ }
             ,

            [Parameter(Mandatory, Position = 1, ParameterSetName = 'NativeCommand')]
            [string]
            $NativeCommand
             ,

            [Parameter(Position = 2, ParameterSetName = 'NativeCommand')]
            [Parameter(Position = 3, ParameterSetName = 'PS')]
            [string]
            $WordToComplete = ''

        )

        if ($PSCmdlet.ParameterSetName -eq 'NativeCommand')
        {
            $Tokens = $null
            $Errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($NativeCommand, [ref]$Tokens, [ref]$Errors)
            $commandAst = $ast.EndBlock.Statements[0].PipelineElements[0]
            $command = $commandAst.GetCommandName()
            $completer = $tabExpansionOptions.NativeArgumentCompleters[$command]
            if (-not $Completer)
            {
                throw "No argument completer registered for command '$Command' (from $NativeCommand)"
            }
            & $completer $WordToComplete $commandAst
        }
        else
        {
            $completer = $tabExpansionOptions.CustomArgumentCompleters["${CommandName}:$ParameterName"]
            if (-not $Completer)
            {
                throw "No argument completer registered for '${CommandName}:$ParameterName'"
            }
            & $completer $CommandName $ParameterName $WordToComplete $commandAst $FakeBoundParameters
        }
    }

    #############################################################################
    #
    # .SYNOPSIS
    # Retrieves a list of argument completers that have been loaded into the
    # PowerShell session.
    #
    # .PARAMETER Name
    # The name of the argument complete to retrieve. This parameter supports
    # wildcards (asterisk).
    #
    # .EXAMPLE
    # Get-ArgumentCompleter -Name *Azure*;
    function Get-ArgumentCompleter
    {
        [CmdletBinding()]
        param ([string[]]
            $Name = '*')

        if (!$updatedTypeData)
        {
            # Define the default display properties for the objects returned by Get-ArgumentCompleter
            [string[]]$properties = "Command", "Parameter"
            Update-TypeData -TypeName 'TabExpansionPlusPlus.ArgumentCompleter' -DefaultDisplayPropertySet $properties -Force
            $updatedTypeData = $true
        }

        function WriteCompleters
        {
            function WriteCompleter($command, $parameter, $native, $scriptblock)
            {
                foreach ($n in $Name)
                {
                    if ($command -like $n)
                    {
                        $c = $command
                        if ($command -and $parameter) { $c += ':' }
                        $description = $tabExpansionDescriptions["${c}${parameter}${native}"]
                        $completer = [pscustomobject]@{
                            Command = $command
                            Parameter = $parameter
                            Native = $native
                            Description = $description
                            ScriptBlock = $scriptblock
                            File = if ($scriptblock.File) { Split-Path -Leaf -Path $scriptblock.File }
                        }

                        $completer.PSTypeNames.Add('TabExpansionPlusPlus.ArgumentCompleter')
                        Write-Output $completer

                        break
                    }
                }
            }

            foreach ($pair in $tabExpansionOptions.CustomArgumentCompleters.GetEnumerator())
            {
                if ($pair.Key -match '^(.*):(.*)$')
                {
                    $command = $matches[1]
                    $parameter = $matches[2]
                }
                else
                {
                    $parameter = $pair.Key
                    $command = ""
                }

                WriteCompleter $command $parameter $false $pair.Value
            }

            foreach ($pair in $tabExpansionOptions.NativeArgumentCompleters.GetEnumerator())
            {
                WriteCompleter $pair.Key '' $true $pair.Value
            }
        }

        WriteCompleters | Sort-Object -Property Native, Command, Parameter
    }

    #############################################################################
    #
    # .SYNOPSIS
    #     Register a ScriptBlock to perform argument completion for a
    #     given command or parameter.
    #
    # .DESCRIPTION
    #
    # .PARAMETER Option
    #
    #     The name of the option.
    #
    # .PARAMETER Value
    #
    #     The value to set for Option. Typically this will be $true.
    #
    function Set-TabExpansionOption
    {
        param (
            [ValidateSet('ExcludeHiddenFiles',
                        'RelativePaths',
                        'LiteralPaths',
                        'IgnoreHiddenShares',
                        'AppendBackslash')]
            [string]
            $Option,

            [object]
            $Value = $true)

        $tabExpansionOptions[$option] = $value
    }

    #endregion Exported functions

    #region Internal utility functions

    #############################################################################
    #
    # This function checks if an attribute argument's name can be completed.
    # For example:
    #     [Parameter(<TAB>
    #     [Parameter(Po<TAB>
    #     [CmdletBinding(DefaultPa<TAB>
    #
    function TryAttributeArgumentCompletion
    {
        param (
            [System.Management.Automation.Language.Ast]
            $ast,

            [int]
            $offset
        )

        $results = @()
        $matchIndex = -1

        try
        {
            # We want to find any NamedAttributeArgumentAst objects where the Ast extent includes $offset
            $offsetInExtentPredicate = {
                param ($ast)
                return $offset -gt $ast.Extent.StartOffset -and
                $offset -le $ast.Extent.EndOffset
            }
            $asts = $ast.FindAll($offsetInExtentPredicate, $true)

            $attributeType = $null
            $attributeArgumentName = ""
            $replacementIndex = $offset
            $replacementLength = 0

            $attributeArg = $asts | Where-Object { $_ -is [System.Management.Automation.Language.NamedAttributeArgumentAst] } | Select-Object -First 1
            if ($null -ne $attributeArg)
            {
                $attributeAst = [System.Management.Automation.Language.AttributeAst]$attributeArg.Parent
                $attributeType = $attributeAst.TypeName.GetReflectionAttributeType()
                $attributeArgumentName = $attributeArg.ArgumentName
                $replacementIndex = $attributeArg.Extent.StartOffset
                $replacementLength = $attributeArg.ArgumentName.Length
            }
            else
            {
                $attributeAst = $asts | Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] } | Select-Object -First 1
                if ($null -ne $attributeAst)
                {
                    $attributeType = $attributeAst.TypeName.GetReflectionAttributeType()
                }
            }

            if ($null -ne $attributeType)
            {
                $results = $attributeType.GetProperties('Public,Instance') |
                Where-Object {
                    # Ignore TypeId (all attributes inherit it)
                    $_.Name -like "$attributeArgumentName*" -and $_.Name -ne 'TypeId'
                } |
                Sort-Object -Property Name |
                ForEach-Object {
                    $propType = [Microsoft.PowerShell.ToStringCodeMethods]::Type($_.PropertyType)
                    $propName = $_.Name
                    New-CompletionResult $propName -ToolTip "$propType $propName" -CompletionResultType Property
                }

                return [PSCustomObject]@{
                    Results = $results
                    ReplacementIndex = $replacementIndex
                    ReplacementLength = $replacementLength
                }
            }
        }
        catch { }
    }

    #############################################################################
    #
    # This function completes native commands options starting with - or --
    # works around a bug in PowerShell that causes it to not complete
    # native command options starting with - or --
    #
    function TryNativeCommandOptionCompletion
    {
        param (
            [System.Management.Automation.Language.Ast]
            $ast,

            [int]
            $offset
        )

        $results = @()
        $replacementIndex = $offset
        $replacementLength = 0
        try
        {
            # We want to find any Command element objects where the Ast extent includes $offset
            $offsetInOptionExtentPredicate = {
                param ($ast)
                return $offset -gt $ast.Extent.StartOffset -and
                $offset -le $ast.Extent.EndOffset -and
                $ast.Extent.Text.StartsWith('-')
            }
            $option = $ast.Find($offsetInOptionExtentPredicate, $true)
            if ($option -ne $null)
            {
                $command = $option.Parent -as [System.Management.Automation.Language.CommandAst]
                if ($command -ne $null)
                {
                    $nativeCommand = [System.IO.Path]::GetFileNameWithoutExtension($command.CommandElements[0].Value)
                    $nativeCompleter = $tabExpansionOptions.NativeArgumentCompleters[$nativeCommand]

                    if ($nativeCompleter)
                    {
                        $results = @(& $nativeCompleter $option.ToString() $command)
                        if ($results.Count -gt 0)
                        {
                            $replacementIndex = $option.Extent.StartOffset
                            $replacementLength = $option.Extent.Text.Length
                        }
                    }
                }
            }
        }
        catch { }

        return [PSCustomObject]@{
            Results = $results
            ReplacementIndex = $replacementIndex
            ReplacementLength = $replacementLength
        }
    }


    #endregion Internal utility functions

    #############################################################################
    #
    # This function is partly a copy of the V3 TabExpansion2, adding a few
    # capabilities such as completing attribute arguments and excluding hidden
    # files from results.
    #
    function global:TabExpansion2
    {
        [CmdletBinding(DefaultParameterSetName = 'ScriptInputSet')]
        Param (
            [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 0)]
            [string]
            $inputScript,

            [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 1)]
            [int]
            $cursorColumn,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 0)]
            [System.Management.Automation.Language.Ast]
            $ast,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 1)]
            [System.Management.Automation.Language.Token[]]
            $tokens,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 2)]
            [System.Management.Automation.Language.IScriptPosition]
            $positionOfCursor,

            [Parameter(ParameterSetName = 'ScriptInputSet', Position = 2)]
            [Parameter(ParameterSetName = 'AstInputSet', Position = 3)]
            [Hashtable]
            $options = $null
        )

        if ($null -ne $options)
        {
            $options += $tabExpansionOptions
        }
        else
        {
            $options = $tabExpansionOptions
        }

        if ($psCmdlet.ParameterSetName -eq 'ScriptInputSet')
        {
            $results = [System.Management.Automation.CommandCompletion]::CompleteInput(
            <#inputScript#>                $inputScript,
            <#cursorColumn#>                $cursorColumn,
            <#options#>                $options)
        }
        else
        {
            $results = [System.Management.Automation.CommandCompletion]::CompleteInput(
            <#ast#>                $ast,
            <#tokens#>                $tokens,
            <#positionOfCursor#>                $positionOfCursor,
            <#options#>                $options)
        }

        if ($results.CompletionMatches.Count -eq 0)
        {
            # Built-in didn't succeed, try our own completions here.
            if ($psCmdlet.ParameterSetName -eq 'ScriptInputSet')
            {
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($inputScript, [ref]$tokens, [ref]$null)
            }
            else
            {
                $cursorColumn = $positionOfCursor.Offset
            }

            # workaround PowerShell bug that case it to not invoking native completers for - or --
            # making it hard to complete options for many commands
            $nativeCommandResults = TryNativeCommandOptionCompletion -ast $ast -offset $cursorColumn
            if ($null -ne $nativeCommandResults)
            {
                $results.ReplacementIndex = $nativeCommandResults.ReplacementIndex
                $results.ReplacementLength = $nativeCommandResults.ReplacementLength
                if ($results.CompletionMatches.IsReadOnly)
                {
                    # Workaround where PowerShell returns a readonly collection that we need to add to.
                    $collection = new-object System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]
                    $results.GetType().GetProperty('CompletionMatches').SetValue($results, $collection)
                }
                $nativeCommandResults.Results | ForEach-Object {
                    $results.CompletionMatches.Add($_)
                }
            }

            $attributeResults = TryAttributeArgumentCompletion $ast $cursorColumn
            if ($null -ne $attributeResults)
            {
                $results.ReplacementIndex = $attributeResults.ReplacementIndex
                $results.ReplacementLength = $attributeResults.ReplacementLength
                if ($results.CompletionMatches.IsReadOnly)
                {
                    # Workaround where PowerShell returns a readonly collection that we need to add to.
                    $collection = new-object System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]
                    $results.GetType().GetProperty('CompletionMatches').SetValue($results, $collection)
                }
                $attributeResults.Results | ForEach-Object {
                    $results.CompletionMatches.Add($_)
                }
            }
        }

        if ($options.ExcludeHiddenFiles)
        {
            foreach ($result in @($results.CompletionMatches))
            {
                if ($result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderItem -or
                    $result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer)
                {
                    try
                    {
                        $item = Get-Item -LiteralPath $result.CompletionText -ErrorAction Stop
                    }
                    catch
                    {
                        # If Get-Item w/o -Force fails, it is probably hidden, so exclude the result
                        $null = $results.CompletionMatches.Remove($result)
                    }
                }
            }
        }
        if ($options.AppendBackslash -and
            $results.CompletionMatches.ResultType -contains [System.Management.Automation.CompletionResultType]::ProviderContainer)
        {
            foreach ($result in @($results.CompletionMatches))
            {
                if ($result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer)
                {
                    $completionText = $result.CompletionText
                    $lastChar = $completionText[-1]
                    $lastIsQuote = ($lastChar -eq '"' -or $lastChar -eq "'")
                    if ($lastIsQuote)
                    {
                        $lastChar = $completionText[-2]
                    }

                    if ($lastChar -ne '\')
                    {
                        $null = $results.CompletionMatches.Remove($result)

                        if ($lastIsQuote)
                        {
                            $completionText =
                            $completionText.Substring(0, $completionText.Length - 1) +
                            '\' + $completionText[-1]
                        }
                        else
                        {
                            $completionText = $completionText + '\'
                        }

                        $updatedResult = New-Object System.Management.Automation.CompletionResult `
                        ($completionText, $result.ListItemText, $result.ResultType, $result.ToolTip)
                        $results.CompletionMatches.Add($updatedResult)
                    }
                }
            }
        }

        if ($results.CompletionMatches.Count -eq 0)
        {
            # No results, if this module has overridden another TabExpansion2 function, call it
            # but only if it's not the built-in function (which we assume if function isn't
            # defined in a file.
            if ($oldTabExpansion2 -ne $null -and $oldTabExpansion2.File -ne $null)
            {
                return (& $oldTabExpansion2 @PSBoundParameters)
            }
        }

        return $results
    }


    #############################################################################
    #
    # Main
    #

    Add-Type @"
using System;
using System.Management.Automation;

public class NativeCommandTreeNode
{
    private NativeCommandTreeNode(NativeCommandTreeNode[] subCommands)
    {
        SubCommands = subCommands;
    }

    public NativeCommandTreeNode(string command, NativeCommandTreeNode[] subCommands)
        : this(command, null, subCommands)
    {
    }

    public NativeCommandTreeNode(string command, string tooltip, NativeCommandTreeNode[] subCommands)
        : this(subCommands)
    {
        this.Command = command;
        this.Tooltip = tooltip;
    }

    public NativeCommandTreeNode(string command, string tooltip, bool argument)
        : this(null)
    {
        this.Command = command;
        this.Tooltip = tooltip;
        this.Argument = true;
    }

    public NativeCommandTreeNode(ScriptBlock completionGenerator, NativeCommandTreeNode[] subCommands)
        : this(subCommands)
    {
        this.CompletionGenerator = completionGenerator;
    }

    public string Command { get; private set; }
    public string Tooltip { get; private set; }
    public bool Argument { get; private set; }
    public ScriptBlock CompletionGenerator { get; private set; }
    public NativeCommandTreeNode[] SubCommands { get; private set; }
}
"@

    # Custom completions are saved in this hashtable
    $tabExpansionOptions = @{
        CustomArgumentCompleters = @{ }
        NativeArgumentCompleters = @{ }
    }
    # Descriptions for the above completions saved in this hashtable
    $tabExpansionDescriptions = @{ }
    # And private data for the above completions cached in this hashtable
    $completionPrivateData = @{ }
}
