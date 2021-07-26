function Get-ServerParent {
    [cmdletbinding()]
    param (
        [object]$InputObject
    )
    process {
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