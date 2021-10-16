using System;

namespace Sqlcollaborative.Dbatools.Validation
{
    /// <summary>
    /// The results of testing linked server connectivity as seen from the server that was linked to.
    /// </summary>
    [Serializable]
    public class LinkedServerResult
    {
        /// <summary>
        /// The name of the server running the tests
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// The name of the instance running the tests
        /// </summary>
        public string InstanceName;

        /// <summary>
        /// The full name of the instance running the tests
        /// </summary>
        public string SqlInstance;

        /// <summary>
        /// The name of the linked server, the connectivity with whom was tested
        /// </summary>
        public string LinkedServerName;

        /// <summary>
        /// The name of the remote computer running the linked server.
        /// </summary>
        public string RemoteServer;

        /// <summary>
        /// The test result
        /// </summary>
        public bool Connectivity;

        /// <summary>
        /// Text interpretation of the result. Contains error messages if the test failed.
        /// </summary>
        public string Result;

        /// <summary>
        /// Creates an empty object
        /// </summary>
        public LinkedServerResult()
        {

        }

        /// <summary>
        /// Creates a test result with prefilled values
        /// </summary>
        /// <param name="ComputerName">The name of the server running the tests</param>
        /// <param name="InstanceName">The name of the instance running the tests</param>
        /// <param name="SqlInstance">The full name of the instance running the tests</param>
        /// <param name="LinkedServerName">The name of the linked server, the connectivity with whom was tested</param>
        /// <param name="RemoteServer">The name of the remote computer running the linked server.</param>
        /// <param name="Connectivity">The test result</param>
        /// <param name="Result">Text interpretation of the result. Contains error messages if the test failed.</param>
        public LinkedServerResult(string ComputerName, string InstanceName, string SqlInstance, string LinkedServerName, string RemoteServer, bool Connectivity, string Result)
        {
            this.ComputerName = ComputerName;
            this.InstanceName = InstanceName;
            this.SqlInstance = SqlInstance;
            this.LinkedServerName = LinkedServerName;
            this.RemoteServer = RemoteServer;
            this.Connectivity = Connectivity;
            this.Result = Result;
        }
    }
}