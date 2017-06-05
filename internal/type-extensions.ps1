# Implement query accelerator for the server object
Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Query -MemberType ScriptMethod -Value {
    Param (
        $Query,
		
        $Database = "master",
        
        $AllTables = $false
    )
    
    if ($AllTables) { ($this.Databases[$Database].ExecuteWithResults($Query)).Tables }
    else { ($this.Databases[$Database].ExecuteWithResults($Query)).Tables[0] }
}