if (-not $ExecutionContext.SessionState.InvokeCommand.GetCommand('Get-Runspace','Function,Cmdlet')) {
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