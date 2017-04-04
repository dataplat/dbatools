
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaCmConnectionParameter", "sqlcollective.dbatools.parameter.DbaCmConnectionParameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbargx", "sqlcollective.dbatools.Utility.RegexHelper") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatime", "sqlcollective.dbatools.Utility.DbaTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadatetime", "sqlcollective.dbatools.Utility.DbaDateTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadate", "sqlcollective.dbatools.Utility.DbaDate") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatimespan", "sqlcollective.dbatools.Utility.DbaTimeSpan") }
catch { }