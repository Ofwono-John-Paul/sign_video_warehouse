"""add video geo columns

Revision ID: aacbde9910d6
Revises: 
Create Date: 2026-03-19 11:51:25.720044

"""
from alembic import op


# revision identifiers, used by Alembic.
revision = 'aacbde9910d6'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    ADD COLUMN IF NOT EXISTS uploader_latitude DOUBLE PRECISION,
                    ADD COLUMN IF NOT EXISTS uploader_longitude DOUBLE PRECISION,
                    ADD COLUMN IF NOT EXISTS geo_source VARCHAR(50);
            END IF;
        END $$;
        """
    )


def downgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    DROP COLUMN IF EXISTS geo_source,
                    DROP COLUMN IF EXISTS uploader_longitude,
                    DROP COLUMN IF EXISTS uploader_latitude;
            END IF;
        END $$;
        """
    )
