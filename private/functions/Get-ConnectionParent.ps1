function Get-ConnectionParent {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [switch]$Database
    )
    process {
        if ($Database) {
            $parentcount = 0
            do {
                if ($null -ne $InputObject.Parent) {
                    $InputObject = $InputObject.Parent
                }
            }
            until ($InputObject.GetType().Name -eq "Database" -or ($parentcount++) -gt 10)

            if ($parentcount -lt 10) {
                $InputObject
            }
        } else {
            $parentcount = 0
            do {
                if ($null -ne $InputObject.Parent) {
                    $InputObject = $InputObject.Parent
                }
            }
            until ($null -ne $InputObject.ConnectionContext -or ($parentcount++) -gt 10)

            if ($parentcount -lt 10) {
                $InputObject
            }
        }
    }
}