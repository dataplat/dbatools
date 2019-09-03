function Invoke-Alter {
    <#
        For stubborn .net objects that won't throw properly
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', "", Justification = "Line 13")]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [object]$Object
    )
    process {
        if ($PSCmdlet.ShouldProcess($Name, "Performing create")) {
            $ErrorActionPreference = 'Stop'
            $EnableException = $true
            $Object.Alter()
        }
    }
}