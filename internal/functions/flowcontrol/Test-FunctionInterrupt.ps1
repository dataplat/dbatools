
function Test-FunctionInterrupt {
    <#
        .SYNOPSIS
            Internal tool, used to gracefully interrupt a function.

        .DESCRIPTION
            This helper function is designed to work in tandem with Stop-Function.
            When gracefully terminating a function, there is a major issue:
            "Return" will only stop the current one of the three blocks (Begin, Process, End).
            All other statements have side effects or produce lots of red text.

            So, Stop-Function writes a variable into the parent scope, that signals the function should cease.
            This function then checks for that very variable and returns true if it is set.

            This avoids having to handle odd variables in the parent function and causes the least impact on contributors.

        .EXAMPLE
            if (Test-FunctionInterrupt) { return }

            The calling function will stop if this function returns true.
       #>
    [CmdletBinding()]
    param (

    )

    $var = Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -ErrorAction Ignore
    if ($var.Value) { return $true }

    return $false
}