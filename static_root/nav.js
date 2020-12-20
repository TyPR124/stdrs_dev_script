var all_targets = {
    "x86_64-unknown-linux-gnu": "64bit Linux GNU",
    "x86_64-pc-windows-gnu": "64bit Windows GNU",
    "x86_64-apple-darwin": "64bit Mac OSX",
};
// Mapping of target OS to /sys/{dir}/
var sys_map = {
    "windows": "/sys/windows/",
    "linux": "/sys/unix/",
    "darwin": "/sys/unix/",
};
// Mapping of target OS to /os/{dir}/
var os_map = {
    "windows": ["/os/windows/"],
    "linux": ["/os/unix/", "/os/linux/"],
    "darwin": ["/os/unix/", "/os/macos/"],
};
function init_target_select() {
    let currently_viewed_target = detect_current_target();
    let target_select = document.createElement("select");
    target_select.id = "target_select";
    for (let key in all_targets) {
        let option = document.createElement("option");
        option.value = key;
        option.text = all_targets[key];
        if (key == currently_viewed_target) {
            option.selected = true;
            window.localStorage.setItem('last_viewed_target', key);
        }
        target_select.appendChild(option);
    }

    let sidebar = document.getElementsByClassName("sidebar")[0];
    let location = sidebar.getElementsByClassName("location")[0];
    // Steeling the class (and therefore style) of location
    target_select.className = location.className;
    target_select.onchange = on_target_change;
    sidebar.insertBefore(target_select, location);
}

function detect_current_target() {
    let url = window.location.href;
    for (let key in all_targets) {
        if (url.indexOf("/" + key + "/") >= 0) {
            return key;
        }
    }
    console.error("Failed to detect target triple in URL");
    return ""
}

async function on_target_change() {
    let new_target = document.getElementById("target_select").value;
    let cur_target = detect_current_target();
    if (!cur_target) {
        window.location.href = "/nightly/" + new_target + "/std/index.html";
        return;
    }
    let new_url = window.location.href.replace(cur_target, new_target);
    let new_os = target_os(new_target);
    let cur_os = target_os(cur_target);
    new_url = new_url.replace(sys_map[cur_os], sys_map[new_os]);
    for (let cur_os_dir of os_map[cur_os]) {
        new_url = new_url.replace(cur_os_dir, os_map[new_os][0]);
    }
    while (new_url.indexOf("/nightly/") > 0) {
        let response = await fetch(new_url);
        if (response.ok) {
            window.location.href = new_url;
            return;
        }
        new_url = url_pop_part(new_url);
    }
    // Fallback to /std/index.html
    window.location.href = "/nightly/" + new_target + "/std/index.html";
}

function url_pop_part(url) {
    return url.substring(0, url.lastIndexOf('/'))
}

function target_os(target) {
    return target.split('-')[2]
}

document.addEventListener("DOMContentLoaded", init_target_select);