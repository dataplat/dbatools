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

Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Invoke -MemberType ScriptMethod -Value {
	Param (
		$Command,
		
		$Database = "master"
	)
	
	else { $this.Databases[$Database].ExecuteNonQuery($Command) }
}

Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Query -MemberType ScriptMethod -Value {
	Param (
		$Query,
		
		$AllTables = $false
	)
	
	if ($AllTables) { ($this.ExecuteWithResults($Query)).Tables }
	else { ($this.ExecuteWithResults($Query)).Tables[0] }
}

Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Invoke -MemberType ScriptMethod -Value {
	Param (
		$Command
	)
	
	else { $this.ExecuteNonQuery($Command) }
}