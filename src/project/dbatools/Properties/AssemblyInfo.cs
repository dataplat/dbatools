using System.Reflection;
using System.Runtime.InteropServices;

// Setting ComVisible to false makes the types in this assembly not visible
// to COM components.  If you need to access a type in this assembly from
// COM, set the ComVisible attribute to true on that type.
[assembly: ComVisible(false)]

// The following GUID is for the ID of the typelib if this project is exposed to COM
[assembly: Guid("7a0d426f-2e98-4851-8af8-c1b2b17c052d")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.Tests")]

// The library projects reach the shared internal helpers, StatementFault first (harness-edits.md, "Operator decision:
// StatementFault.Surface required at caller-try sites (2026-11-02)", point 3).
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.agent")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.computer")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.core")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.database")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.hadr")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.maintenance")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.migration")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.performance")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.replication")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.security")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.ssis")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("dbatools.xevents")]
