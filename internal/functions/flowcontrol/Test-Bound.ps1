function Test-Bound {
    <#
    .SYNOPSIS
        Helper function that tests if a parameter was bound.

    .DESCRIPTION
        Helper function that tests if one or more parameters was bound.

    .PARAMETER ParameterName
        The name(s) of the parameter that is tested for being bound.
        By default, the check is true when AT LEAST one was bound.

    .PARAMETER Not
        Reverses the result. Returns true if NOT bound and false if bound.

    .PARAMETER And
        All specified parameters must be present, rather than at least one of them.

    .PARAMETER Min
        At least the specified number of parameters out of the specified parameters must be present. Default is 1.

    .PARAMETER Max
        A maximum of the specified number of parameters out of the specified parameters may be present. Default is the length of ParameterName.

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

        Returns whether any of the specified parameters was not bound.

    .EXAMPLE
        Test-Bound -ParameterName 'MinimumBuild', 'MaxBehind', 'Latest' -Max 1

        Tests for mutually exclusive but necessary parameters.

    .EXAMPLE
        Test-Bound -ParameterName 'Database', 'AllDatabases', 'ExcludeDatabase' -Min 0 -Max 1

        Tests for mutually exclusive but optional parameters.
    #>
    # Do not be tempted to use [CmdletBinding()] here, this will subtly change the way this function's parameters are bound, and break it.
    param (
        [string[]]
        $ParameterName,

        [Alias('Reverse')]
        [switch]
        $Not,

        [switch]
        $And,

        [int]
        $Min = 1,
        [int]
        $Max = $ParameterName.Length,

        [object]
        $BoundParameters = $($ExecutionContext.SessionState.PSVariable.Get('psboundparameters').Value)
    )

    if (-not $ParameterName) { return $false }
    if (-not $BoundParameters) { return $false }

    if ($And) {
        $Min = $ParameterName.Length
    }

    $usedParameters = 0
    foreach ($name in $ParameterName) {
        if ($BoundParameters.ContainsKey($name)) {
            $usedParameters++
        }
    }

    if ($usedParameters -ge $Min -and $usedParameters -le $Max) {
        $test = $true
    } else {
        $test = $false
    }

    return ((-not $Not) -eq $test)
}