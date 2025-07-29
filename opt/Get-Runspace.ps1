# Provides a compatibility implementation of Get-Runspace for PowerShell v3/v4
# Loaded automatically by dbatools.psm1 for PSVersion < 5

if (-not (Get-Command -Name Get-Runspace -ErrorAction SilentlyContinue)) {
    function Get-Runspace {
        $type = [type]'System.Management.Automation.Runspaces.Runspace'
        if ($type.GetMethod('GetRunspaces')) {
            $allRunspaces = [System.Management.Automation.Runspaces.Runspace]::GetRunspaces()
            foreach ($rs in $allRunspaces) {
                [PSCustomObject]@{
                    Id           = $rs.Id
                    Name         = $rs.Name
                    Type         = $rs.RunspaceType
                    State        = $rs.RunspaceStateInfo.State
                    Availability = $rs.Availability
                    InstanceId   = $rs.InstanceId
                }
            }
        } elseif ($type.GetProperty('DefaultRunspace')) {
            $rs = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
            if ($rs) {
                [PSCustomObject]@{
                    Id           = $rs.Id
                    Name         = $rs.Name
                    Type         = $rs.RunspaceType
                    State        = $rs.RunspaceStateInfo.State
                    Availability = $rs.Availability
                    InstanceId   = $rs.InstanceId
                }
            }
        } else {
            Write-Warning "Unable to retrieve runspace information in this environment."
            return $null
        }
    }
}