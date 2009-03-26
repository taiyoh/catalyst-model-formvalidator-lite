package Catalyst::Model::FormValidator::Lite;

use strict;
use warnings;
use Scalar::Util qw/blessed refaddr/;
use base qw/Catalyst::Model/;
__PACKAGE__->mk_classdata('validator_profile');

our $VERSION = '0.001_2';

use FormValidator::Lite;
use YAML;

sub new {
    my $self = shift;
    $self = $self->next::method(@_);
    my ($c) = @_;
    my $conf = $c->config->{validator};
    $self->validator_profile(
        do {
            $conf->{profile} ||= '';
            if ( -f $conf->{profile} ) {
                no warnings 'once';
                $c->log->debug("Loaded FV::Lite Profile \"$conf->{profile}\"");
                local $YAML::UseAliases = 0;
                my $data = YAML::Dump( YAML::LoadFile( $conf->{profile} ) );
                utf8::decode($data);
                YAML::Load($data);    # XXX: remove yaml aliases
            }
            else {
                {};
            }
        }
    );
    my $constraints = $conf->{constraints};
    $constraints = [$constraints] unless ref $constraints;
    FormValidator::Lite->load_constraints(@$constraints);
    $self;
}

sub ACCEPT_CONTEXT {
    my $self = shift;
    my ($c) = @_;

    return $self->build_per_context_instance(@_) unless ref $c;
    my $key = blessed $self ? refaddr $self : $self;
    return $c->stash->{"__InstancePerContext_${key}"} ||= $self->build_per_context_instance(@_);
}

sub build_per_context_instance {
    my $self  = shift;
    my $c     = shift;
    my $form = {};
    my $action = $c->req->{action};
    $form = $self->validator_profile->{ $action }
        if exists $self->validator_profile->{ $action };
    my $klass = 'Catalyst::Model::FormValidator::Lite::PerRequest';
    my $rule = $_[1] ? +{ @_ } : $_[0];
    $rule ||= {};
    $rule = +{ @$rule } if ref $rule eq 'ARRAY';
    return $klass->new( $c->req, $form, $rule );
}

package Catalyst::Model::FormValidator::Lite::PerRequest;
use base qw/Class::Data::Inheritable/;
use Clone qw/clone/;
__PACKAGE__->mk_classdata('action_cache');
__PACKAGE__->action_cache({});

sub new {
    my $pkg = shift;
    my ( $req, $form, $rule ) = @_;
    my $validator = FormValidator::Lite->new($req);
    my $self = bless {
        _validator => $validator,
        _rule      => {},
        _message   => {},
    }, $pkg;
    $self->_form_action($form, $req->{action});
    $self->_merge_rule($rule || {});
    $self->{_validator}->set_message( $self->{_message} );
    $self->{_validator}->check( %{ $self->{_rule} } );
    $self;
}

sub _form_action {
    my ( $self, $form, $action ) = @_;
    if (my $cache = clone($self->action_cache->{$action})) {
        $self->{_rule} = $cache->{rule};
        $self->{_message} = $cache->{message};
        return;
    }
    my $cache;
    for my $n ( keys %$form ) {
        for my $r ( @{ $form->{$n} } ) {
            my $rule;
            if ( $rule = $r->{rule} ) {
                if ( ref $rule eq 'ARRAY' ) {
                    push @{ $cache->{rule}->{$n} }, $rule;
                    $rule = $rule->[0];
                }
                else {
                    push @{ $cache->{rule}->{$n} }, $rule;
                }
            }
            else {
                $rule = $r->{self_rule};
            }
            $rule = lc($rule);
            $cache->{message}->{"${n}.${rule}"} = $r->{message} if $rule;
        }
    }
    $self->action_cache->{$action} = clone($cache);
    $self->{_rule}    = $cache->{rule};
    $self->{_message} = $cache->{message};
}

sub _merge_rule {
    my ( $self, $rule ) = @_;
    for my $n ( keys %$rule ) {
        push @{ $self->{_rule}->{$n} }, values(%$rule);
    }
}

sub AUTOLOAD {
    my $self = shift;
    (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
    return if $method eq "DESTROY";

    $self->{_validator}->$method(@_) if $self->{_validator}->can($method);
}

1;
