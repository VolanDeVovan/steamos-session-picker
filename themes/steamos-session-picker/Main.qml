import QtQuick
import "../../ui"
import "../../ui/entries.js" as Entries

// The picker, as SDDM's greeter.
//
// This is the whole boot path now: sddm.service starts the greeter, the greeter
// loads this file, and the card the room picks is started by SDDM itself. There
// is no session in between and nothing of ours runs as root — see
// docs/mechanism.md.
//
// SDDM hands a theme four things, all of them ready before this file loads:
//
//   sessionModel   every session the machine has, in SDDM's own order
//   userModel      the accounts it will offer, and which one was last
//   sddm.login()   authenticate and start a session, by row in sessionModel
//   config.*       theme.conf, and theme.conf.user beside it
//
// Everything visual is in ui/, shared with the overlay that runs inside Game
// Mode, so the two look and behave the same.
Item {
    id: root

    // SDDM sizes the greeter window to the screen and this item to the window.
    // Fall back to a design-sized surface so the file can still be loaded by
    // hand for a look.
    width: 1920
    height: 1080

    // Which account the session is started for. The picker chooses a session,
    // not a person: on a console there is one account and asking would be
    // noise. `user=` in theme.conf overrides it where that is not true.
    readonly property string loginUser: {
        if (config.user && config.user !== "")
            return config.user;
        if (userModel.lastUser && userModel.lastUser !== "")
            return userModel.lastUser;
        return users.count > 0 ? users.itemAt(0).name : "";
    }

    // `hide=` names entries the way a person does — plasmax11.desktop — and
    // sessionModel's `file` role is the path SDDM read them from. Both ends go
    // through Entries.fileName(), so a full path in theme.conf works too.
    readonly property var hidden: String(config.hide || "").split(",").map(function (s) {
        return Entries.fileName(s.trim());
    }).filter(function (s) {
        return s !== "";
    })

    // sessionModel is a C++ model, and QML can only read one through something
    // that instantiates it. These two Repeaters are that something: they build
    // nothing visible, and the bindings below depend on their count, which is
    // what makes the list appear as soon as the delegates exist.
    Item {
        visible: false

        Repeater {
            id: sessions
            model: sessionModel
            delegate: Item {
                required property int index
                required property string name
                required property string comment
                required property string file
            }
        }

        Repeater {
            id: users
            model: userModel
            delegate: Item {
                required property string name
            }
        }
    }

    readonly property var cards: {
        var raw = [];
        for (var i = 0; i < sessions.count; i++) {
            var item = sessions.itemAt(i);
            if (!item || hidden.indexOf(Entries.fileName(item.file)) !== -1)
                continue;
            raw.push({
                name: item.name,
                comment: item.comment,
                file: item.file,
                index: item.index
            });
        }
        return Entries.build(raw);
    }

    Picker {
        id: picker
        anchors.fill: parent
        sessions: root.cards

        // Nowhere to go back to: this is the first thing after the firmware.
        cancellable: false

        onActivated: function (card) {
            const session = root.cards[card];
            if (root.loginUser === "") {
                launching = false;
                message = "No account to log in as";
                return;
            }
            // Empty password on purpose. It is not a way past authentication:
            // PAM is asked and answers, and the answer is yes because the
            // account is in the nopasswdlogin group. Somewhere without that
            // rule this is a failed login and the card comes back — which is
            // exactly what should happen. See docs/mechanism.md.
            sddm.login(root.loginUser, "", session.index);
        }

        // The list arrives after this file loads, so the first card is selected
        // here rather than at construction.
        onSessionsChanged: if (currentIndex >= sessions.length)
            currentIndex = 0
    }

    Connections {
        target: sddm

        // The greeter is torn down from under us on success, so there is
        // nothing to do but keep the overlay up until that happens.
        function onLoginFailed() {
            picker.launching = false;
            picker.message = "That session could not be started";
        }
    }
}
