using System;
using Microsoft.Azure.Management.WebSites;
using Microsoft.Rest;
using SlavaGu.ConsoleAppLauncher;

namespace dotnetsample
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Starting");

            var subscriptionId = ConsoleApp.Run("az", "account show --query id -o tsv").Output.Trim();
            var token = ConsoleApp.Run("az", "account get-access-token --query accessToken -o tsv").Output.Trim();

            Console.WriteLine($"Running with Sub: {subscriptionId}");
            Console.WriteLine($"Running with Token: {token}");


            var serviceCreds = new TokenCredentials(token, "Bearer");

            var webClient = new WebSiteManagementClient(serviceCreds);
            webClient.SubscriptionId = subscriptionId;

            var functionSecrets = webClient.WebApps.ListFunctionSecrets("funcRestSpecTest", "testfuncx8b7a", "testfunc");

            if (functionSecrets.Name == null)
            {
                Console.WriteLine("Due to spec issue #2 we see unpopulated Name properties");
            }

            if (functionSecrets.Key == null)
            {
                Console.WriteLine("Due to spec issue #1 we end up here");
            }

        }
    }
}
