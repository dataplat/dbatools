# Provides a compatibility implementation of Get-Runspace for PowerShell v3/v4
# Loaded automatically by dbatools.psm1 for PSVersion < 5

if (-not (Get-Command -Name Get-Runspace -ErrorAction SilentlyContinue)) {
    function Get-Runspace {
        try {
            $runspaces = [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces.Values
            foreach ($rs in $runspaces) {
                $availability = switch ($rs.State.ToString()) {
                    'Running' { 'Available' }
                    default   { 'NotAvailable' }
                }
                [PSCustomObject]@{
                    Id           = $rs.RunspaceGuid
                    Name         = $rs.Name
                    Type         = $rs.GetType().Name
                    State        = $rs.State
                    Availability = $availability
                    InstanceId   = $rs.RunspaceGuid
                }
            }
        } catch {
            Write-Warning "Unable to enumerate dbatools-managed runspaces: $_"
        }
    }
}