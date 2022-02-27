using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui.ConversationSummary {

public class ReactionsController : Object {
    public signal void box_activated(Widget widget);

    private Conversation conversation;
    private Account account;
    private ContentItem content_item;
    private StreamInteractor stream_interactor;

    private HashMap<string, Gee.List<Jid>> reactions = new HashMap<string, Gee.List<Jid>>();

    private ReactionsWidget? widget = null;

    public ReactionsController(Conversation conversation, ContentItem content_item, StreamInteractor stream_interactor) {
        this.conversation = conversation;
        this.account = conversation.account;
        this.content_item = content_item;
        this.stream_interactor = stream_interactor;
    }

    public void init() {
        HashMap<string, Gee.List<Jid>> reactions = stream_interactor.get_module(Reactions.IDENTITY).get_item_reactions(conversation, content_item);
        if (reactions.size > 0) {
            initialize_widget();
        }
        foreach (string reaction in reactions.keys) {
            foreach (Jid jid in reactions[reaction]) {
                reaction_added(reaction, jid);
            }
        }

        stream_interactor.get_module(Reactions.IDENTITY).reaction_added.connect((account, content_item_id, jid, reaction) => {
            if (this.content_item.id == content_item_id) {
                reaction_added(reaction, jid);
            }
        });
        stream_interactor.get_module(Reactions.IDENTITY).reaction_removed.connect((account, content_item_id, jid, reaction) => {
            if (this.content_item.id == content_item_id) {
                reaction_removed(reaction, jid);
            }
        });
    }

    private void initialize_widget() {
        widget = new ReactionsWidget() { visible=true };
        widget.emoji_picked.connect((emoji) => {
            stream_interactor.get_module(Reactions.IDENTITY).add_reaction(conversation, content_item, emoji);
        });
        widget.emoji_clicked.connect((emoji) => {
            if (account.bare_jid in reactions[emoji]) {
                stream_interactor.get_module(Reactions.IDENTITY).remove_reaction(conversation, content_item, emoji);
            } else {
                stream_interactor.get_module(Reactions.IDENTITY).add_reaction(conversation, content_item, emoji);
            }
        });
        box_activated(widget);
    }

    public void reaction_added(string reaction, Jid jid) {
        if (widget == null) {
            initialize_widget();
        }

        if (!reactions.has_key(reaction)) {
            reactions[reaction] = new ArrayList<Jid>(Jid.equals_func);
        }
        if (jid.equals_bare(account.bare_jid) && reactions[reaction].contains(jid)) {
            return;
        }
        reactions[reaction].add(jid);

        if (reactions[reaction].size == 0) return;

        widget.update_reaction(reaction, reactions[reaction].size, reactions[reaction].contains(account.bare_jid), update_tooltip(reaction));
    }

    public void reaction_removed(string reaction, Jid jid) {
        if (!reactions.has_key(reaction)) return;
        reactions[reaction].remove(jid);

        if (reactions[reaction].size > 0) {
            widget.update_reaction(reaction, reactions[reaction].size, reactions[reaction].contains(account.bare_jid), update_tooltip(reaction));
        } else {
            widget.remove_reaction(reaction);
            reactions.unset(reaction);
        }

        if (reactions.size == 0) {
            widget.destroy();
            widget = null;
        }
    }

    private Gee.List<string> update_tooltip(string reaction) {
        var name_list = new ArrayList<string>();
        if (reactions[reaction].size > 0) {
            if (account.bare_jid in reactions[reaction]) {
                name_list.add(_("You"));
            }
            foreach (Jid jid in reactions[reaction]) {
                if (jid.equals(account.bare_jid)) continue;

                name_list.add(Util.get_participant_display_name(stream_interactor, conversation, jid));
            }
        }
        return name_list;
    }
}

public class ReactionsWidget : Grid {

    public signal void emoji_picked(string emoji);
    public signal void emoji_clicked(string emoji);

    private HashMap<string, Label> reaction_counts = new HashMap<string, Label>();
    private HashMap<string, Button> reaction_buttons = new HashMap<string, Button>();
    private MenuButton add_button;

    public ReactionsWidget() {
        this.row_spacing = this.column_spacing = 5;
        this.margin_top = 2;

        add_button = new MenuButton() { tooltip_text= _("Add reaction"), visible=true };
        add_button.get_style_context().add_class("reaction-box");
        Image add_image = new Image.from_icon_name("dino-emoticon-add-symbolic", IconSize.SMALL_TOOLBAR) { margin_left=5, margin_right=5, visible=true };
        add_button.add(add_image);

        EmojiChooser chooser = new EmojiChooser();
        chooser.emoji_picked.connect((emoji) => {
            emoji_picked(emoji);
        });
        add_button.set_popover(chooser);
    }

    public void update_reaction(string reaction, int count, bool own, Gee.List<string> names) {
        if (!reaction_buttons.has_key(reaction)) {
            Label reaction_label = new Label("<span size='small'>" + reaction + "</span>") { use_markup=true, visible=true };
            Label count_label = new Label("") { use_markup=true, visible=true };
            Button button = new Button() { visible=true };
            button.get_style_context().add_class("reaction-box");
            Box reaction_box = new Box(Orientation.HORIZONTAL, 4) { visible=true };
            reaction_box.add(reaction_label);
            reaction_box.add(count_label);
            button.add(reaction_box);

            reaction_counts[reaction] = count_label;
            reaction_buttons[reaction] = button;

            this.attach(button, (reaction_buttons.size - 1) % 10, (reaction_buttons.size - 1) / 10, 1, 1);
            if (add_button.get_parent() != null) this.remove(add_button);
            this.attach(add_button, reaction_buttons.size % 10, reaction_buttons.size / 10, 1, 1);


            button.clicked.connect(() => {
                emoji_clicked(reaction);
            });
        }

        reaction_counts[reaction].label = "<span size='small'>" + count.to_string() + "</span>";
        if (own) {
            reaction_buttons[reaction].get_style_context().add_class("own-reaction");
        } else {
            reaction_buttons[reaction].get_style_context().remove_class("own-reaction");
        }

        // Build tooltip
        StringBuilder tooltip_builder = new StringBuilder ();
        for (int i = 0; i < names.size - 1; i++) {
            tooltip_builder.append(names[i]);
            if (i < names.size - 2) tooltip_builder.append(", ");
        }
        if (names.size > 1) {
            tooltip_builder.append(" and ");
        }
        tooltip_builder.append(names[names.size - 1]);
        tooltip_builder.append(" reacted with " + reaction);
        reaction_buttons[reaction].set_tooltip_text(tooltip_builder.str);
    }

    public void remove_reaction(string reaction) {
        reaction_buttons[reaction].destroy();
    }
}

}