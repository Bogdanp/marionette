user_pref("marionette.port", @(or port 2828));
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.firstRunURL", "");

@when[(hash? user.js)
      @in[(k v) (in-hash user.js)]{
	  user_pref(@~s[k], @~js[v]);
      }]
