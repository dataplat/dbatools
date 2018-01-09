# Only update on first import
if (-not ([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported)) {
    # Implement query accelerator for the server object
    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Query -MemberType ScriptMethod -Value {
        param (
            $Query,

            $Database = "master",

            $AllTables = $false
        )

        if ($AllTables) { ($this.Databases[$Database].ExecuteWithResults($Query)).Tables }
        else { ($this.Databases[$Database].ExecuteWithResults($Query)).Tables[0] }
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Invoke -MemberType ScriptMethod -Value {
        param (
            $Command,

            $Database = "master"
        )

        $this.Databases[$Database].ExecuteNonQuery($Command)
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Query -MemberType ScriptMethod -Value {
        param (
            $Query,

            $AllTables = $false
        )

        if ($AllTables) { ($this.ExecuteWithResults($Query)).Tables }
        else { ($this.ExecuteWithResults($Query)).Tables[0] }
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Invoke -MemberType ScriptMethod -Value {
        param (
            $Command
        )

        $this.ExecuteNonQuery($Command)
    } -ErrorAction Ignore
}