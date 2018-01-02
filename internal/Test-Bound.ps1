function Test-Bound {
    <#
        .SYNOPSIS
            Helperfunction that tests, whether a parameter was bound.

        .DESCRIPTION
            Helperfunction that tests, whether a parameter was bound.

        .PARAMETER ParameterName
            The name(s) of the parameter that is tested for being bound.
            By default, the check is true when AT LEAST one was bound.

        .PARAMETER Not
            Reverses the result. Returns true if NOT bound and false if bound.

        .PARAMETER And
            All specified parameters must be present, rather than at least one of them.

        .PARAMETER BoundParameters
            The hashtable of bound parameters. Is automatically inherited from the calling function via default value. Needs not be bound explicitly.

        .EXAMPLE
            if (Test-Bound "Day")
            {

            }

            Snippet as part of a function. Will check whether the parameter "Day" was bound. If yes, whatever logic is in the conditional will be executed.

        .EXAMPLE
            Test-Bound -Not 'Login', 'Spid', 'ExcludeSpid', 'Host', 'Program', 'Database'

            Returns whether none of the parameters above were specified.

        .EXAMPLE
            Test-Bound -And 'Login', 'Spid', 'ExcludeSpid', 'Host', 'Program', 'Database'

            Returns whether any of the specified parameters was not bound
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]
        $ParameterName,

        [Alias('Reverse')]
        [switch]
        $Not,

        [switch]
        $And,

        [object]
        $BoundParameters = (Get-PSCallStack)[0].InvocationInfo.BoundParameters
    )

    if ($And) {
        $test = $true
    }
    else {
        $test = $false
    }

    foreach ($name in $ParameterName) {
        if ($And) {
            if (-not $BoundParameters.ContainsKey($name)) { $test = $false }
        }
        else {
            if ($BoundParameters.ContainsKey($name)) { $test = $true }
        }
    }

    return ((-not $Not) -eq $test)
}