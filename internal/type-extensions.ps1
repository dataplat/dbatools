# Implement query accelerator
Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Query -MemberType ScriptMethod -Value {
    Param (
        $Database,
        $Query
    )
    
    ($this.Databases[$Database].ExecuteWithResults($Query)).Tables[0]
}