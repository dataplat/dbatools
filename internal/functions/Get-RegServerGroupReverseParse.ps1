function Get-RegServerGroupReverseParse ($object) {
    if ($object.Name -eq 'DatabaseEngineServerGroup') {
        $object.Name
    }
    else {
        $name = @()
        do {
            $name += $object.Name
            $object = $object.Parent
        }
        until ($object.Name -eq 'DatabaseEngineServerGroup')
        
        [array]::Reverse($name)
        $name -join '\'
    }
}