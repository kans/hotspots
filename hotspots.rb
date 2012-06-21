require 'sinatra'
require 'net/http'
require 'open-uri'
require 'github_api'

def install_hooks
  repo = ['Racker', 'Reach']

  github = Github.new basic_auth:'', repo:'reach', org:'racker'
  github.repos.hooks.create 'user-name','repo-name', name:"web"
end

configure do  install_hooks
end


# // return an options object to request something from the github v3 api
# var github_request = function(repo, method, id){
#   var self = this;
#   // TODO: safify
#   var path = util.format("/repos/%s/%s/hooks", self.api_config.org, repo);
#   if (id){
#     path += '/' + id;
#   }
#   return {
#     method: method,
#     port: 443,
#     headers: {
#       'Authorization': utils.create_basic_auth(self.api_config.username, self.api_config.apikey)
#     },
#     host: url.parse(self.api_config.url).host,
#     path: path
#   };
# };

# var get_hooks = function(repo, callback){
#   var self = this;
#   var list_hooks = {};
#   var options;
#   options = self.github_request(repo, "GET");

#   utils.request_maker(options, callback);
# };

# var delete_hooks = function(repo, result, callback){
#   var self = this;
#   var to_delete = [];
#   var to_keep = [];
#   // look at http status
#   if (result.res.statusCode === 401){
#     throw new Error('Your config is probably wrong for github- they don\'t like your creds.'+
#       JSON.stringify(result.data));
#   }else if (result.res.statusCode === 404){
#     throw new Error('Your config is probably wrong for github repos- they don\'t know it exists?');
#   }
#   // iterate through the hooks list for a given org/repo
#   _.each(JSON.parse(result.data), function(hook){
#     var options;
#     var delete_hook = true;
#     if (hook.message){
#       throw new Error('Error: github says -> ' + hook.message);
#     }
#     // if the hook matches one we'd want to make, make sure its kosher
#     if (hook.config.url === self.get_api_url()){
#       // have we seen it before (sometimes dead ones pile up)
#       if (_.indexOf(to_keep, hook.config.url) !== -1){
#         log.log("DELETEing hook: " + hook.url, " because its a dup");
#       } else if (hook.active !== true){
#         log.log("DELETEing hook: " + hook.url, " because its not active");
#       } else if (hook.name !== 'web'){
#         log.log("DELETEing hook: " + hook.url, " because its not named 'web'");
#       } else if(_.indexOf(hook.events, self.events) === -1){
#         log.log("DELETEing hook: " + hook.url,
#           " because its not listening to pull_requests");
#       } else if(hook.last_response.status !== "unused" && hook.last_response.status !== "ok"){
#         log.log("DELETEing hook: " + hook.url, " because its " + hook.last_response.status);
#       } else{
#         delete_hook = false;
#       }
#       if (!delete_hook){
#         log.debug("\n\nKEEPing hook: " + JSON.stringify(hook)+'\n\n');
#         to_keep.push(hook.config.url);
#       }else{
#         options = self.github_request(repo, "DELETE", hook.id);
#         to_delete.push(function(cb){
#           utils.request_maker(options, cb);
#         });
#       }
#     }
#   });
#   async.parallel(to_delete, function(err, results){
#     callback(err, result, to_keep);
#   });
# };
# var add_hooks = function(repo, results, existing_hooks, callback){
#   var options;
#   var self = this;
#   var url;

#   url = self.get_api_url();
#   // if we already have a hook for this repo, skip it
#   if (_.indexOf(existing_hooks, url) !== -1){
#     log.debug("Hook already exists. Not creating.");
#     return callback(null, null);
#   }
#   // otherwise, lets make a new hook
#   options = self.github_request(repo, "POST");
#   options.headers['Content-Type'] = 'application/json';
#   options.post_data = {
#     name: "web",
#     active: true,
#     events: [self.events],
#     config: {
#       url: url,
#       content_type: "json"
#     }
#   };
#   log.log("Creating github web hook");
#   utils.request_maker(options, callback);
# };
# var parse_response = function(result, callback){
#   var data;
#   var err = null;

#   if (result) {
#     try {
#       data = JSON.parse(result.data);
#       if (data.message) {
#         err = data.message;
#       }
#     } catch (e) {
#       log.error(e);
#     }
#   }

#   callback(err, data);
# };

# exports.install = utils.make_class({
#   init: function(config, project, cb){
#     var self = this;
#     var repos;
#     self.api_config = config;
#     self.project = project;

#     self.github_request = _.bind(github_request, self);

#     // XXX TODO: Giant hack
#     if (!_.isArray(self.api_config.repo)) {
#       self.api_config.repo = [ self.api_config.repo ];
#     }
#     // do stuff (after binding to self)
#     _.each(self.api_config.repo, function(repo) {
#       async.waterfall([
#         _.bind(get_hooks, self, repo),
#         _.bind(delete_hooks, self, repo),
#         _.bind(add_hooks, self, repo),
#         _.bind(parse_response, self)
#       ], cb);
#     });
#   },
#   get_api_url: function(){
#     var self = this;
#     return util.format("http://%s:%s/api/github/%s",
#       settings.external_ipv4,
#       settings.github_hook_listen_port,
#       self.project.name);
#   },
#   events: "pull_request"
# });