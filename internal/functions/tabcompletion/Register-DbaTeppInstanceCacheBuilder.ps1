function Register-DbaTeppInstanceCacheBuilder {
    <#
        .SYNOPSIS
            Registers a scriptblock used to build the TEPP cache from an instance connection.

        .DESCRIPTION
            Registers a scriptblock used to build the TEPP cache from an instance connection.
            Used only on import of the module.

        .PARAMETER ScriptBlock
            The ScriptBlock used to build the cache.

            The ScriptBlock may assume the following two variables to exist:
            - $FullSmoName (A string containing the full SMO name as presented by the DbaInstanceParameter class-interpreted input)
            - $server (An SMO connection object)

        .PARAMETER Slow
            This switch implies a gathering process that takes too much time to be performed synchronously.
            Basically, when retrieving the information takes more than 25ms on an average server (on top of establishing the original connection), this switch should be set.

        .EXAMPLE
            Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock

            Registers the scriptblock stored in the aptly named variable $ScriptBlock as a fest cache building scriptblock.
            Note: The scriptblock must execute swiftly! (less than 25ms)

        .EXAMPLE
            Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock -Slow

            Registers the scriptblock stored in the aptly named variable $ScriptBlock as a slow cache building scriptblock.
            This is suitable for cache building scriptblocks that take a while to execute.

        .NOTES
            Additional information about the function.
       #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock,

        [switch]
        $Slow
    )

    if ($Slow -and ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow -notcontains $ScriptBlock)) {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow.Add($ScriptBlock)
    } elseif ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast -notcontains $ScriptBlock) {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast.Add($ScriptBlock)
    }
}