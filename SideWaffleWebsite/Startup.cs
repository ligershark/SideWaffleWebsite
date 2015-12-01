using Microsoft.AspNet.Builder;
using Microsoft.Extensions.DependencyInjection;
using SideWaffleWebsite.Models;

namespace SideWaffleWebsite
{
    public class Startup
    {
        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // Add MVC services to the services container.
            services.AddMvc();
            services.AddTransient<Client>();
        }

        // Configure is called after ConfigureServices is called.
        public void Configure(IApplicationBuilder app)
        {
            app.UseMvc();

            // Add static files to the request pipeline.
            app.UseStaticFiles();

            // Add MVC to the request pipeline.
            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller}/{action}/{id?}",
                    defaults: new { controller = "Home", action = "Index" });
            });

            /*
            *   For development purposes
            *   Comment the lines below when ready to commit changes
            */
            //app.UseDeveloperExceptionPage();
        }
    }
}
