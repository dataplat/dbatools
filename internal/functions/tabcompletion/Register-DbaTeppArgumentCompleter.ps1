function Register-DbaTeppArgumentCompleter {
    <#
        .SYNOPSIS
            Registers a parameter for a prestored Tepp.

        .DESCRIPTION
            Registers a parameter for a prestored Tepp.
            This function allows easily registering a function's parameter for Tepp in the function-file, rather than in a centralized location.

        .PARAMETER Command
            Name of the command whose parameter should receive Tepp.
            Supports multiple commands at the same time in order to optimize performance.

        .PARAMETER Parameter
            Name of the parameter that should be Tepp'ed.

        .PARAMETER Name
            Name of the Tepp Completioner to use.
            Defaults to the parameter name.
            Best practice requires a Completioner to be named the same as the completed parameter, in which case this parameter needs not be specified.
            However sometimes that may not be universally possible, which is when this parameter comes in.

        .PARAMETER All
            Whether this TEPP applies to all commands in dbatools that have the specified parameter.

        .EXAMPLE
            Register-DbaTeppArgumentCompleter -Command Get-DbaDbBackupHistory -Parameter Database

            Registers the "Database" parameter of the Get-DbaDbBackupHistory to receive Database-Tepp
       #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingEmptyCatchBlock", "")]
    param (
        [string[]]$Command,
        [string[]]$Parameter,
        [string]$Name,
        [switch]$All
    )

    #region ScriptBlock
    $scriptBlock = {
        param (
            $commandName,
            $parameterName,
            $wordToComplete,
            $commandAst,
            $fakeBoundParameter
        )

        if ($teppScript = [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::GetTeppScript($commandName, $parameterName)) {
            $start = Get-Date
            $teppScript.LastExecution = $start
            $teppScript.LastDuration = New-Object System.TimeSpan(-1) # Null it, just in case. It's a new start.

            try { $ExecutionContext.InvokeCommand.InvokeScript($true, ([System.Management.Automation.ScriptBlock]::Create($teppScript.ScriptBlock.ToString())), $null, @($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)) }
            catch { }

            $teppScript.LastDuration = (Get-Date) - $start
        }
    }
    #endregion ScriptBlock

    foreach ($p in $Parameter) {
        $lowername = $PSBoundParameters.Name

        if ($null -eq $lowername) {
            $lowername = $p.ToLowerInvariant()
        } else {
            $lowername = $lowername.ToLowerInvariant()
        }

        if ($All) { [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::AddTabCompletionSet("*", $p, $lowername) }
        else {
            foreach ($c in $Command) {
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::AddTabCompletionSet($c, $p, $lowername)
            }
        }

        if ($script:TEPP) {
            TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $Command -ParameterName $p -ScriptBlock $scriptBlock
        } else {
            Register-ArgumentCompleter -CommandName $Command -ParameterName $p -ScriptBlock $scriptBlock
        }
    }
}