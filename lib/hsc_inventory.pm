package hsc_inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Data::Validate::MySQL qw(is_int is_date is_boolean is_varchar is_text is_enum);
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(encode_base64url);
use DateTime;
use DateTime::Format::HTTP;
use Imager::QRCode;
use UPC;

our $VERSION = '0.1';

#prefix '/hsc_inventory';
set serializer => 'JSON';

get '/' => sub {
    my $schema = schema('hsc_inventory');
    template 'index';
};

get '/mass' => sub {
    my $schema = schema('hsc_inventory');
    template 'mass';
};

get '/item/:item_id' => sub {
    my $schema = schema('hsc_inventory');
    template 'item';
};

before sub {
    # check auth token
    my $token = params->{token};

    header 'Access-Control-Allow-Origin' => '*';
    return if request->method eq 'GET' || request->path eq '/api/get_token';

    my $schema = schema('hsc_inventory');
    my $token_obj = $schema->resultset('Token')->single({token => $token, expire_time => {'>' => \'now()'}}) if $token;

    if (!$token_obj) {
        # TODO: use 403 if the user is logged in but not allowed to access a resource
        status 401;
        halt {error => 'This request requires a valid token'};
    } else {
        # store the user
        var 'user' => $token_obj->user;
    }
};

prefix '/api';

# takes usersname/pass and returns a token (and expiration info?)
post '/get_token' => sub {
    my $username = params->{username};
    my $pass = params->{password};

    # check for username/hashed pass
    if ($username && $pass) {
        my $schema = schema('hsc_inventory');
        my $password_hash = sha256_hex(config->{password_salt} . $pass),
        my $user = $schema->resultset('User')->find({username => $username});
        if ($user && $user->password_hash eq $password_hash) {
            my $rand = int(rand(time)*100);
            my $token = encode_base64url($username . $rand);
            my $expire = config->{token_expire};
            $user->create_related('tokens', {token => $token, expire_time => \"date_add(now(), INTERVAL $expire DAY)"});
            return {token => $token};
        }
    }

    return {error => 'Invalid username/password'};
};

any ['get', 'put', 'options'] => '/get_token' => sub {
    status 405;
};

# list all items
get '/items' => sub {
    my $schema = schema('hsc_inventory');

    my $offset = params->{offset} || 0;
    debug("OFFSET: $offset");

    my $search_params = {};
    if (params->{search_terms}) {
        # FIXME:
#        $search_params->{} = ;
    }

    # FIXME: validate sort field
    my $sort_by = params->{sort_by} || 'name';

    # TODO: allow user to specify columns returned?

    my @rows = $schema->resultset('Inventory')->search({}, {
            rows => 20,
            offset => $offset,
            sort_by => $sort_by,
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        })->all;

    my $total = $schema->resultset('Inventory')->search({}, {
            sort_by => $sort_by,
        })->count;
    for (@rows) {
        $_->{uri} = config->{base_uri} . 'items/' . $_->{inventory_id};
    }

    return {total => $total, items => \@rows};
};

# creates a new item and returns its ID
# FIXME: Location header should contain the URL for the newly created item
post '/items' => sub {
    my $schema = schema('hsc_inventory');

    my $columns = $schema->source('Inventory')->columns_info;
    my @errors = ();

    my $create_params = {};
    for my $col (keys %$columns) {
        next if ($col eq 'c_time' || $col eq 'm_time' || $col eq 'inventory_id');

        my $col_meta = $columns->{$col};
        if (!$col_meta->{is_nullable} && (! defined params->{$col} || params->{$col} eq '')) {
            if (! defined $col_meta->{default_value}) {
                push @errors, "Missing required field: '$col'";
            }
            next;
        }

        # nullify the field if possible
        if ($col_meta->{is_nullable} && params->{$col} eq '') {
            $create_params->{$col} = undef;
            next;
        }

        next unless defined params->{$col};

        my $result;
        if ($col_meta->{data_type} eq 'DATE') {
            $result = is_date(params->{$col});

        } elsif ($col_meta->{data_type} eq 'INT') {
            $result = is_int(params->{$col});

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $result = is_boolean(params->{$col});

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $result = is_enum(params->{$col}, @{$col_meta->{extra}->{list}});

        } else {

            if ($col_meta->{size}) {
                $result = is_varchar(params->{$col}, $col_meta->{size});
                
            } else {
                $result = is_text(params->{$col});
            }
        }

        if (! defined $result) {
            push @errors, "$col contains invalid data";
        } else {
            $create_params->{$col} = params->{$col};
        }
    }


    if (@errors) {
        return {errors => \@errors};
    }

    my $item = $schema->resultset('Inventory')->create($create_params) or die "Could not create inventory";
    my $id = $item->inventory_id;
    header 'Location' => uri_for("/api/items/$id");

    return {item_id => $id};
};

any ['put', 'options'] => '/items' => sub {
    status 405;
};

# returns a hashref of field names as keys and field type/size
get '/items/fields' => sub {
    my $columns = schema('hsc_inventory')->source('Inventory')->columns_info;
    my $return = {};

    for my $col (keys %$columns) { 
        my $col_meta = $columns->{$col};

        if ($col_meta->{data_type} eq 'DATE') {
            $return->{$col} = {type => 'date'};

        } elsif ($col_meta->{data_type} eq 'INT') {
            $return->{$col} = {type => 'int'};

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $return->{$col} = {type => 'flag'};

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $return->{$col} = {type => 'list', values => $col_meta->{extra}->{list}};

        } else {
            $return->{$col} = {type => 'text', size => $col_meta->{size} ? $col_meta->{size} : 0};
        }

        $return->{$col}->{pretty_name} = join(' ', map(ucfirst, map(lc, split('_', $col))));
        $return->{$col}->{pretty_name} = 'Modified' if ($col eq 'm_time');
        $return->{$col}->{pretty_name} = 'Created' if ($col eq 'c_time');

        $return->{$col}->{required} = $col_meta->{is_nullable} ? 0 : 1;
        $return->{$col}->{not_editable} = 1 if $col eq 'c_time' || $col eq 'm_time' || $col eq 'inventory_id' || $col eq 'version';
    }
    return $return;
};

# gets item info based given an ID (also handles HEAD requests)
get '/items/:item_id' => sub {
    my $id = params->{item_id};

    my $schema = schema('hsc_inventory');
    my $item = $schema->resultset('Inventory')->find($id, {result_class => 'DBIx::Class::ResultClass::HashRefInflator'});
    my $version = delete $item->{version};
    my @datetime = split(/[\-\s:]/, $item->{m_time} || $item->{c_time});
    my $dt = DateTime->new(
        year      => $datetime[0],
        month     => $datetime[1],
        day       => $datetime[2],
        hour      => $datetime[3],
        minute    => $datetime[4],
        second    => $datetime[5],
        time_zone => 'UTC',
    );
    my $last_modified = DateTime::Format::HTTP->format_datetime($dt);

    if ($item) {
        status 201;
        header 'Last-Modified'  => $last_modified;
        header 'ETag'           => $version;
        header 'Content-Length' => length(to_json($item));

        return request->is_head ? '' : $item;

    } else {
        status 'not_found';
        return "Item '$id' not found";
    }
};

# updates an item's info given the info and an ID
put '/items/:item_id' => sub {
    my $id = params->{item_id};
    return {error => 'No item_id specified'} unless $id;

    # TODO: some sort of auth check on which cols a user can edit?
    #    maybe some users can only check in/out items, others can edit details
    my $schema = schema('hsc_inventory');

    my $item = $schema->resultset('Inventory')->find($id);
    return {error => "Invalid item ID: $id"} unless $item;

    my $columns = $schema->source('Inventory')->columns_info;
    my @errors = ();

    my $update_params = {};
    my $params = params;

    delete $params->{version};
    $item->{version} ||= 0;
    $update_params->{version} = $item->{version}+1;

    for my $col (keys %$params) {
        next if ($col eq 'c_time' || $col eq 'm_time' || $col eq 'item_id');

        my $col_meta = $columns->{$col};
        next unless defined $col_meta;

        # nullify the field if possible
        if ($col_meta->{is_nullable} && params->{$col} eq '') {
            $update_params->{$col} = undef;
            next;
        }

        my $result;
        if ($col_meta->{data_type} eq 'DATE') {
            $result = is_date(params->{$col});

        } elsif ($col_meta->{data_type} eq 'INT') {
            $result = is_int(params->{$col});

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $result = is_boolean(params->{$col});

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $result = is_enum(params->{$col}, @{$col_meta->{extra}->{list}});

        } else {

            if ($col_meta->{size}) {
                $result = is_varchar(params->{$col}, $col_meta->{size});
                
            } else {
                $result = is_text(params->{$col});
            }
        }

        if (! defined $result) {
            push @errors, "$col contains invalid data";
        } else {
            $update_params->{$col} = params->{$col};
        }
    }
    
    if (@errors) {
        return {errors => \@errors};
    }

    $item->update($update_params) or die "Could not update item";
    return {item_id => $id};
};

# check in/out items

# checking out an item only returns success or error (for now)
post '/items/:item_id/check_out' => sub {
    my $user = var 'user';
    my $schema = schema('hsc_inventory');
    my $item = $schema->resultset('Inventory')->find(params->{item_id});
    if (! $item->is_loanable) {
        return {error => 'Item is not loanable!'};
    }
    if ($item->on_loan_to) {
        return {error => 'Item is already loaned out!'};
    }
    my $return_date = params->{expected_return_date} || \'date_add(now(), INTERVAL 7 day)';
    eval {
    $item->update({
            on_loan_to => $user->username,
            expected_return_date => $return_date,
        });
    };
    if ($@) {
        return {error => 'There was an error checking out this item'};
    } else {
        return {success => 1};
    }
};

# checking in an item also returns success or error
post '/items/:item_id/check_in' => sub {
    my $user = var 'user';
    my $schema = schema('hsc_inventory');
    my $item = $schema->resultset('Inventory')->find(params->{item_id});
    if (! $item->is_loanable) {
        return {error => 'Item is not loanable!'};
    }
    eval {
    $item->update({
            on_loan_to => undef,
            expected_return_date => undef,
        });
    };
    if ($@) {
        return {error => 'There was an error checking in this item'};
    } else {
        return {success => 1};
    }
};

del '/items/:item_id' => sub {
    my $id = params->{item_id};
    return {error => 'No item_id specified'} unless $id;

    my $schema = schema('hsc_inventory');

    my $item = $schema->resultset('Inventory')->find($id);
    return {error => "Invalid item ID: $id"} unless $item;

    $item->delete() or die "Could not delete item";
    return {success => 1};
};

get '/scan/:item_id' => sub {
    my $id = params->{item_id};
    my $size = params->{size} || 4;

    if (!$id) {
        response->status(404);
        return;
    }

    my $schema = schema('hsc_inventory');
    my $item = $schema->resultset('Inventory')->find($id, {result_class => 'DBIx::Class::ResultClass::HashRefInflator'});

    if ($item) {
        # FIXME: long cache time
        # FIXME: allow other image formats
        my @datetime = split(/[\-\s:]/, $item->{c_time});
        my $dt = DateTime->new(
            year      => $datetime[0],
            month     => $datetime[1],
            day       => $datetime[2],
            hour      => $datetime[3],
            minute    => $datetime[4],
            second    => $datetime[5],
            time_zone => 'UTC',
        );
        my $last_modified = DateTime::Format::HTTP->format_datetime($dt);

        my $image_data;
        my $img;
        if (params->{format} && lc(params->{format}) eq 'upc') {
            $img = UPC::upc($id, $size);

        } else {
            my $qr = Imager::QRCode->new( size => $size, level => 'L');
            $img = $qr->plot($id);
        }
        $img->write(data => \$image_data, type => 'png') or die;

        header 'Content-Length' => length($image_data);

        status 201;
        header 'Last-Modified'  => $last_modified;
        header 'Content-Type' => 'image/png';

        return request->is_head ? '' : $image_data;

    } else {
        status 'not_found';
        return "Item '$id' not found";
    }
};

# FIXME: add OPTIONS routes to show available interactions for resources (in Allow header)
# body can contain details

true;
