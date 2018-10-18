function Invoke-Create {
    <#
        For stubborn .net objects that won't throw properly
    #>
    [CmdletBinding()]
    param (
        [object]$Object
    )
    process {
        $ErrorActionPreference = 'Stop'
        $EnableException = $true
        $Object.Create()
    }
}