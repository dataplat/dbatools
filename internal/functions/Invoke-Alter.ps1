function Invoke-Alter {
    <#
        For stubborn .net objects that won't throw properly
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [object]$Object
    )
    process {
        if ($Pscmdlet.ShouldProcess($Name, "Performing create")) {
            $ErrorActionPreference = 'Stop'
            $EnableException = $true
            $Object.Alter()
        }
    }
}