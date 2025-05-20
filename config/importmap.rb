# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "react" # @19.1.0
pin "react-dom" # @19.1.0
pin "react-spring" # @10.0.0
pin "@react-spring/animated", to: "@react-spring--animated.js" # @10.0.0
pin "@react-spring/core", to: "@react-spring--core.js" # @10.0.0
pin "@react-spring/rafz", to: "@react-spring--rafz.js" # @10.0.0
pin "@react-spring/shared", to: "@react-spring--shared.js" # @10.0.0
pin "@react-spring/types", to: "@react-spring--types.js" # @10.0.0
pin "@react-spring/web", to: "@react-spring--web.js" # @10.0.0
