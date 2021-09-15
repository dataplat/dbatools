function Invoke-Create {
    <#
        For stubborn .net objects that won't throw properly
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [object]$Object
    )
    process {
        if ($Object.Name) {
            $Name = $Object.Name
        } else {
            $Name = "target object"
        }
        if ($Pscmdlet.ShouldProcess($Name, "Performing create")) {
            $ErrorActionPreference = 'Stop'
            $EnableException = $true
            $Object.Create()
        }
    }
}