function Test-DbaDeprecation {
    <#
        .SYNOPSIS
            Tests whether a function or one of its parameters was called by a bad name.

        .DESCRIPTION
            Tests whether a function or one of its parameters was called by a bad name.
            This allows giving deprecation warnings - once per session - whenever a user uses something we are planning on removing.

            For example, when renaming a function, we give a grace period by adding an Alias for that function with its old name.
            However, we do not want to carry along this alias forever, so we give warning ahead of time using this function.
            When reaching the specified version, we then can safely remove the alias.

            Furthermore, this function is used for testing, whether such a removal was properly done.

        .PARAMETER DeprecatedOn
            The version this parameter or alias will be removed in.
            Generally, deprecated parameters and aliases should only be removed on major releases.

        .PARAMETER FunctionName
            Automatically filled with the calling function.
            The name of the function that contains either a deprecated alias or parameter.

        .PARAMETER Call
            The InvocationInfo of the calling function.
            Automatically filled.

        .PARAMETER Parameter
            The parameter that has become deprecated.
            On renamed parameters, keep a parameter-alias. This function will notice, when the alias is used.

        .PARAMETER Alias
            The alias of the command that will be deprecated.

        .PARAMETER CustomMessage
            This function will generate a default message. However, this may not always be appropriate.
            Use CustomMessage to tailor a response to the necessity of the moment.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .EXAMPLE
            PS C:\> Test-DbaDeprecation -DeprecatedOn "1.0.0.0" -Parameter 'Details'

            Will - once per session - complain if the parameter 'Details' is used.
            Will cause tests to fail, if it's still in the code after release 1.0.0.0.

        .EXAMPLE
            PS C:\> Test-DbaDeprecation -DeprecatedOn "1.0.0.0" -Alias Copy-SqlDatabase

            Will - once per session - complain if the alias 'Copy-SqlDatabase' is used.
            Will cause tests to fail, if it's still in the code after release 1.0.0.0.
       #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Version]
        $DeprecatedOn,

        [string]
        $FunctionName = (Get-PSCallStack)[0].Command,

        [object]
        $Call = (Get-PSCallStack)[0].InvocationInfo,

        [Parameter(ParameterSetName = "Param", Mandatory)]
        [string]
        $Parameter,

        [Parameter(ParameterSetName = "Alias", Mandatory)]
        [string]
        $Alias,

        [string]
        $CustomMessage,

        [bool]
        $EnableException = $EnableException
    )

    switch ($PSCmdlet.ParameterSetName) {
        "Param" {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Call.Line, [ref]$null, [ref]$null)
            $objects = $ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
            $sub = $objects | Where-Object Parent -Like "$($Call.InvocationName)*" | Select-Object -First 1

            if ($sub.CommandElements | Where-Object ParameterName -eq $Parameter) {
                if ($CustomMessage) { $Message = $CustomMessage }
                else { $Message = "Using the parameter $Parameter is deprecated. This parameter will be removed in version $DeprecatedOn or before, check in the documentation what parameter to use instead" }

                Write-Message -Message $Message -Level Warning -FunctionName $FunctionName -Once "Deprecated.Alias.$Alias"
            }
        }

        "Alias" {
            if ($Alias -eq $Call.InvocationName) {
                if ($CustomMessage) { $Message = $CustomMessage }
                else { $Message = "Using the alias $Alias is deprecated. This alias will be removed in version $DeprecatedOn or before, use $FunctionName instead. Invoke-DbatoolsRenameHelper can also help rename commands within your scripts." }

                Write-Message -Message $Message -Level Warning -FunctionName $FunctionName -Once "Deprecated.Alias.$Alias"
            }
        }
    }
}