
function Was-Bound
{
    <#
        .SYNOPSIS
            Helperfunction that tests, whether a parameter was bound.
        
        .DESCRIPTION
            Helperfunction that tests, whether a parameter was bound.
        
        .PARAMETER ParameterName
            The name of the parameter that is tested for being bound.
    
        .PARAMETER Not
            Rverses the result. Returns true if NOT bound and false if bound.
        
        .PARAMETER BoundParameters
            The hashtable of bound parameters. Is automatically inherited from the calling function via default value. Needs not be bound explicitly.
        
        .EXAMPLE
            if (Was-Bound "Day")
            {
                
            }
    
            Snippet as part of a function. Will check whether the parameter "Day" was bound. If yes, whatever logic is in the conditional will be executed.
        
        .NOTES
            Additional information about the function.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $ParameterName,
        
        [Alias('Reverse')]
        [switch]
        $Not,
        
        [object]
        $BoundParameters = (Get-PSCallStack)[0].InvocationInfo.BoundParameters
    )
    
    return ((-not $Not) -eq $BoundParameters.ContainsKey($ParameterName))
}
