// Core
import "jquery-ui/ui/version"
import "jquery-ui/ui/keycode"
import "jquery-ui/ui/unique-id"
import "jquery-ui/ui/tabbable"
import "jquery-ui/ui/focusable"
import "jquery-ui/ui/position"
import "jquery-ui/ui/widget"      // define $.widget
import "jquery-ui/ui/plugin"      // <-- define $.ui.plugin (add/call)

// Widgets-base usados por outros
import "jquery-ui/ui/widgets/mouse"
import "jquery-ui/ui/widgets/draggable"   // usa $.ui.plugin
import "jquery-ui/ui/widgets/resizable"   // usa $.ui.plugin
import "jquery-ui/ui/widgets/sortable"
import "jquery-ui/ui/widgets/button"

// Os que você realmente usa na UI
import "jquery-ui/ui/widgets/datepicker"
import "jquery-ui/ui/widgets/dialog"
import "jquery-ui/ui/widgets/tabs"