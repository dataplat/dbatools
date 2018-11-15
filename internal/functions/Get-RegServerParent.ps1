function Get-RegServerParent {
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
        until ($null -ne $InputObject.ServerConnection -or $parentcount++ -gt 10)


        if ($parentcount -lt 10) {
            $InputObject
        }
    }
}