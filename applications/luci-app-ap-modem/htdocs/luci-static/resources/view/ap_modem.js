'use strict';
'require view';
'require uci';
'require form';

return view.extend({
    load: function() {
        return Promise.all([
            uci.load('ap_modem')
        ]);
    },

    render: function() {

        var m, s, o, ss;

        m = new form.Map('ap_modem', _('Access AP / Modem'),
            _('Allows clients in the local network to access AP or modem on different subnet.'));

        s = m.section(form.NamedSection, 'config', 'ap_modem', _('Global Settings'));
        s.anonymous = true;
        s.addremove = false;


        o = s.option(form.Flag, 'enabled', _('Enable'));
        o.rmempty  = false;

        o = s.option(form.Flag, 'snat_enabled', _('Enable SNAT for modem management'));
        o.rmempty = false;
        o.default = o.disabled;

        o = s.option(form.Value, 'snat_dest_ip', _('SNAT destination IP'), _('Usually modem management IP, e.g. 192.168.1.1'));
        o.datatype = 'ip4addr';
        o.placeholder = '192.168.1.1';
        o.depends('snat_enabled', '1');

        o = s.option(form.Value, 'snat_ip', _('SNAT source IP'), _('Usually one WAN virtual IP on modem subnet, e.g. 192.168.1.254'));
        o.datatype = 'ip4addr';
        o.placeholder = '192.168.1.254';
        o.depends('snat_enabled', '1');

        s = m.section(form.NamedSection, 'config', 'ap_modem', _('Interface Settings'));
        s.anonymous = true;
        s.addremove = false;

        [
            {id:"lan", title:_("LAN"), subtitle:_("AP on LAN side"), placeholder:"192.168.31.254", 
                example:_("<br>For example, you want to access the AP, its IP address is 192.168.31.1, but the client and the router are not in its subnet, so it cannot be connected. "
                    + "Then you can add 192.168.31.254 here, the client will be able to access 192.168.31.1 after saving and applying.")},
            {id:"wan", title:_("WAN"), subtitle:_("AP / Modem on WAN side"), placeholder:"192.168.1.254", 
                example:_("<br>For example, you want to access the modem, its IP address is 192.168.1.1, but because it uses PPPoE bridge mode, so it cannot be connected. "
                    + "Then you can add 192.168.1.254 here, the client will be able to access 192.168.1.1 after saving and applying.")},
        ].forEach(function(vif) {
            s.tab(vif.id, vif.title);

            o = s.taboption(vif.id, form.SectionValue, '__'+vif.id+'__', form.NamedSection, vif.id, null,
                vif.subtitle, _('Here add the IP address of the same subnet as the target device, but not the same as the target device. <br>Do not add IPs already used by other devices.') + vif.example);

            ss = o.subsection;
            ss.anonymous = true;

            o = ss.option(form.DynamicList, 'ipaddr', _('Virtual IP'), _('Supports "IP/MASK", "IP/PREFIX", and pure "IP" format, pure "IP" assumes a prefix of 24 bits'));
            o.datatype    = 'ipmask4';
            o.placeholder = vif.placeholder;
        });

        return m.render();
    }
});
