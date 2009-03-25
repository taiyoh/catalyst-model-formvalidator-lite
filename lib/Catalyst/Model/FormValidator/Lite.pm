package Catalyst::Model::FormValidator::Lite;

use strict;
use warnings;
use Scalar::Util qw/blessed refaddr/;
use base qw/Catalyst::Model/;
__PACKAGE__->mk_classdata('validator_profile');

our $VERSION = '0.001_1';

use FormValidator::Lite;
use YAML ();

sub new {
    my $self = shift;
    $self = $self->next::method(@_);
    my ($c) = @_;
    my $conf = $c->config->{validator};
    $self->validator_profile(
        do {
            no warnings 'once';
            $conf->{profile} ||= '';
            if ( -f $conf->{profile} ) {
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
    $form  = $self->validator_profile->{ $c->req->{action} }
        if exists $self->validator_profile->{ $c->req->{action} };
    my $klass = 'Catalyst::Model::FormValidator::Lite::PerRequest';
    return $klass->new( $c->req, $form, @_ );
}

package Catalyst::Model::FormValidator::Lite::PerRequest;

sub new {
    my $pkg = shift;
    my ( $req, $form, @args ) = @_;
    my $validator = FormValidator::Lite->new($req);
    my $self = bless {
        _validator => $validator,
        _rule      => {},
        _message   => {},
    }, $pkg;
    $self->_load_action($form, @args);
    $self;
}

sub _load_action {
    my ( $self, $form, @args ) = @_;
    for my $n ( keys %$form ) {
        for my $r ( @{ $form->{$n} } ) {
            my $rule;
            if ( $rule = $r->{rule} ) {
                if ( ref $rule eq 'ARRAY' ) {
                    push @{ $self->{_rule}->{$n} }, [@$rule];
                    $rule = $rule->[0];
                }
                else {
                    push @{ $self->{_rule}->{$n} }, $rule;
                }
            }
            else {
                $rule = $r->{self_rule};
            }
            $rule = lc($rule);
            $self->{_message}->{"${n}.${rule}"} = $r->{message}
              if $rule;
        }
    }
    $self;
}

sub add_rule {
    my $self = shift;
    my $new_rule = {};
    if ( $_[1] ) {
        $new_rule = +{@_};
    }
    elsif ( $_[0] ) {
        $new_rule = $_[0];
        $new_rule = +{@$new_rule} if ref $new_rule eq 'ARRAY';
    }
    $self->{_rule} = { %{ $self->{_rule} }, %$new_rule };
}

sub add_rule {
    my $self = shift;
    my $new_rule = {};
    if ( $_[1] ) {
        $new_rule = +{@_};
    }
    elsif ( $_[0] ) {
        $new_rule = $_[0];
        $new_rule = +{@$new_rule} if ref $new_rule eq 'ARRAY';
    }
    $self->{_rule} = { %{ $self->{_rule} }, %$new_rule };
}

sub has_error {
    my $self = shift;
    $self->{_validator}->set_message( $self->{_message} );
    $self->{_validator}->check( %{ $self->{_rule} } );
    $self->{_validator}->has_error;
}

sub set_invalid_form {
    my $self = shift;
    $self->{_validator}->set_error(@_);
}

sub AUTOLOAD {
    my $self = shift;
    (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
    return if $method eq "DESTROY";

    $self->{_validator}->$method(@_) if $self->{_validator}->can($method);
}

1;
