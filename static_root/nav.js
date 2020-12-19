var all_targets = {
    "x86_64-unknown-linux-gnu": "64bit Linux GNU",
    "x86_64-pc-windows-gnu": "64bit Windows GNU",
    "x86_64-apple-darwin": "64bit Mac OSX",
};
function init_target_select() {
    var currently_viewed_target = detect_current_target();
    var target_select = document.createElement("select");
    target_select.id = "target_select";
    for (var key in all_targets) {
        var option = document.createElement("option");
        option.value = key;
        option.text = all_targets[key];
        if (key == currently_viewed_target) {
            option.selected = true;
            window.localStorage.setItem('last_viewed_target', key);
        }
        target_select.appendChild(option);
    }

    var sidebar = document.getElementsByClassName("sidebar")[0];
    var location = sidebar.getElementsByClassName("location")[0];
    // Steeling the class (and therefore style) of location
    target_select.className = location.className;
    target_select.onchange = () => {
        var new_target = target_select.value;
        window.location.href = "nightly/" + new_target + "/std/index.html";
    };
    sidebar.insertBefore(target_select, location);
}

function detect_current_target() {
    var url = window.location.href;
    for (var key in all_targets) {
        if (url.indexOf("/" + key + "/") >= 0) {
            return key;
        }
    }
    console.error("Failed to detect target triple in URL");
    return ""
}

document.addEventListener("DOMContentLoaded", init_target_select);